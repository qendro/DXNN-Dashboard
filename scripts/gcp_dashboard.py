"""JSON presentation adapter for GCP, executed only in the AWS-Deployment image.

Resource mutation, retries, locking, verification and ownership stay in
AWS-Deployment/scripts/gcp_manager.py. This adapter only serializes its results
for the dashboard, using the same shape as oci_dashboard.py.
"""
import contextlib
import importlib.util
import io
import json
import os
import sys
from pathlib import Path

# The dashboard passes the old OCI-style verb; Compute Engine only has a hard reset.
VERBS = {'reboot': 'reset'}


def load_cli():
    scripts = Path(os.environ['GCP_HOST_ROOT']) / 'scripts'
    sys.path.insert(0, str(scripts))
    spec = importlib.util.spec_from_file_location('gcp_manager', scripts / 'gcp_manager.py')
    cli = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cli)
    return cli


def snapshot(manager, store, cli):
    instances, errors = [], []
    for record in store.records():
        item = {k: record.get(k) for k in ('instance_id', 'name', 'region', 'zone', 'project', 'progress')}
        item['state'] = 'UNKNOWN'
        ssh = record.get('ssh') or {}
        item['ssh'] = {'username': ssh.get('username'),
                       'private_key': str(cli.host_path(ssh['private_key'])) if ssh.get('private_key') else None}
        machine = record.get('machine') or {}
        item.update(vcpus=machine.get('vcpus'), memory_gbs=machine.get('memory_gb'))
        if record.get('instance_id') and record.get('zone'):
            try:
                instance = manager.get_instance(record['project'], record['zone'], record['name'])
                if instance is None:
                    # Deleted by terminate, a Spot delete action, or outside this tool.
                    item['state'] = 'TERMINATED'
                elif str(instance.id) != record['instance_id']:
                    errors.append(f'{record["name"]} now names a different VM; refusing to show it as this record.')
                else:
                    item.update(state=cli.lifecycle_state(instance.status), gce_status=instance.status,
                                machine_type=cli.last(instance.machine_type),
                                provisioning=instance.scheduling.provisioning_model or 'STANDARD',
                                time_created=instance.creation_timestamp or None,
                                addresses=manager.addresses(instance))
            except Exception:
                errors.append(f'Could not refresh {record["name"]}; saved launch record retained.')
        instances.append(item)
    return instances, errors


def describe(error):
    if hasattr(error, 'code') and hasattr(error, 'message'):
        return f'GCP request failed: HTTP {int(error.code)} {error.message}. Refresh before retrying.'
    if type(error).__name__ == 'DefaultCredentialsError':
        return 'GCP credentials not found. Run gcloud auth application-default login on the host, or set GCP_CREDENTIALS_FILE.'
    return f'Operation failed ({type(error).__name__}); saved progress is retained. Refresh before retrying.'


def execute(cli):
    argv = sys.argv[1:]
    planning = '--mount-plan' in argv
    argv = [arg for arg in argv if arg != '--mount-plan']
    summary = bool(argv and argv[0] == 'summary')
    if argv and argv[0] in VERBS:
        argv[0] = VERBS[argv[0]]
    args = cli.parser().parse_args((['launch'] + argv[1:]) if summary else argv)
    if planning:
        cli.mount_plan(args)
        return 0
    if summary:
        cfg = cli.load_config(args.config)
        public = {k: cfg.get(k) for k in ('name', 'project', 'region', 'zone', 'mode', 'provisioning',
                                          'spot_termination_action', 'machine_type', 'image', 'boot_disk',
                                          'network', 'network_tags')}
        public['ssh'] = {k: cfg['ssh'].get(k) for k in ('username', 'private_key')}
        print(json.dumps({'ok': True, 'summary': public}))
        return 0
    store = cli.common.Store(cli.STATE, 'GCP')
    manager = cli.Manager(store)
    result = {'ok': True, 'instances': []}
    with store.lock():
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                if args.command != 'list':
                    manager.command(args)
        except cli.Error as error:
            result.update(ok=False, error=str(error))
        except Exception as error:
            result.update(ok=False, error=describe(error))
        instances, errors = snapshot(manager, store, cli)
        result['instances'] = instances
        if errors:
            result.update(ok=False, error=' '.join(filter(None, [result.get('error'), *errors])))
    print(json.dumps(result))
    return 0 if result['ok'] else 1


def main():
    os.umask(0o077)
    cli = load_cli()
    try:
        return execute(cli)
    except cli.Error as error:
        print(json.dumps({'ok': False, 'instances': [], 'error': str(error)}))
        return 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as error:
        # Do not echo YAML parser context or credential values.
        print(json.dumps({'ok': False, 'instances': [],
                          'error': f'GCP adapter failed ({type(error).__name__}); check the CLI, configuration and host paths.'}))
        sys.exit(1)

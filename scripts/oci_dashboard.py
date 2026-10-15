"""JSON presentation adapter, executed only in the AWS-Deployment image.

Resource mutation, retries, locking, verification and ownership stay in the
existing oci_manager. This adapter only serializes its results for the dashboard.
"""
import contextlib
import importlib.util
import io
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


def load_cli():
    filename = Path(os.environ['OCI_HOST_ROOT']) / 'scripts/oci_manager.py'
    spec = importlib.util.spec_from_file_location('oci_manager', filename)
    cli = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cli)
    return cli


def utc_timestamp(value):
    if not isinstance(value, datetime):
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat()


def snapshot(manager, store, cli):
    instances, errors = [], []
    for record in store.records():
        item = {k: record.get(k) for k in
                ('instance_id', 'name', 'region', 'progress')}
        item['state'] = 'UNKNOWN'
        ssh = record.get('ssh') or {}
        item['ssh'] = {k: ssh.get(k) for k in ('username', 'private_key')}
        if ssh.get('private_key'):
            item['ssh']['private_key'] = str(cli.host_path(ssh['private_key']))
        if record.get('instance_id'):
            try:
                _, api, instance = manager.resolve(record['instance_id'], record['region'])
                shape = instance.shape_config
                if shape is None:
                    shapes = cli.all_data(api['compute'].list_shapes,
                                          compartment_id=instance.compartment_id,
                                          availability_domain=instance.availability_domain)
                    shape = cli.exact(shapes, lambda candidate: candidate.shape == instance.shape,
                                      'instance shape metadata')
                item.update(name=instance.display_name, state=instance.lifecycle_state,
                            ad=instance.availability_domain, shape=instance.shape,
                            ocpus=getattr(shape, 'ocpus', None),
                            memory_gbs=getattr(shape, 'memory_in_gbs', None),
                            time_created=utc_timestamp(getattr(instance, 'time_created', None)),
                            addresses=manager.addresses(api, instance))
            except Exception as error:
                # OCI eventually removes terminated resources from get_instance.
                if record.get('progress') == 'terminated' and getattr(error, 'status', None) == 404:
                    item['state'] = 'TERMINATED'
                else:
                    errors.append('Could not refresh ' + record['instance_id'] + '; saved launch record retained.')
        instances.append(item)
    return instances, errors


def main():
    os.umask(0o077)
    cli = load_cli()
    try:
        return execute(cli)
    except cli.Error as error:
        print(json.dumps({'ok': False, 'instances': [], 'error': str(error)}))
        return 1


def execute(cli):
    argv = sys.argv[1:]
    planning = '--mount-plan' in argv
    argv = [arg for arg in argv if arg != '--mount-plan']
    summary = bool(argv and argv[0] == 'summary')
    # Reuse the CLI's YAML validation and exact launch key mount planning.
    args = cli.parser().parse_args((['launch'] + argv[1:]) if summary else argv)
    if planning:
        cli.mount_plan(args)
        return 0
    if summary:
        cfg = cli.load_config(args.config)
        public = {k: cfg.get(k) for k in ('name', 'compartment_id', 'region',
                  'availability_domain', 'mode', 'image', 'shape', 'ocpus', 'memory_gbs', 'network')}
        public['ssh'] = {k: cfg['ssh'].get(k) for k in ('username', 'private_key')}
        print(json.dumps({'ok': True, 'summary': public}))
        return 0
    store = cli.Store()
    manager = cli.Manager(cli.auth_config(), store)
    result = {'ok': True, 'instances': []}
    with store.lock():
        try:
            # Human CLI progress is replaced with public saved-record progress.
            with contextlib.redirect_stdout(io.StringIO()):
                if args.command != 'list':
                    manager.command(args)
        except cli.Error as error:
            result.update(ok=False, error=str(error))
        except cli.oci.exceptions.ServiceError as error:
            result.update(ok=False, error=f'OCI request failed: HTTP {error.status}, code={error.code}, request ID={error.request_id}. Refresh before retrying.')
        except Exception as error:
            result.update(ok=False, error=f'Operation failed ({type(error).__name__}); saved progress is retained. Refresh before retrying.')
        instances, errors = snapshot(manager, store, cli)
        result['instances'] = instances
        if errors:
            result.update(ok=False, error=' '.join(filter(None, [result.get('error'), *errors])))
    print(json.dumps(result))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as error:
        # Do not echo YAML/INI parser context or credential values.
        print(json.dumps({'ok': False, 'instances': [],
                          'error': f'OCI adapter failed ({type(error).__name__}); check the CLI, configuration and host paths.'}))
        sys.exit(1)

"""Focused compatibility checks against the real OCI parser; no cloud calls."""
import contextlib
import io
import json
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import oci_dashboard as adapter


class AdapterTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cli = adapter.load_cli()

    def run_adapter(self, argv, cli):
        output = io.StringIO()
        with patch.object(adapter, 'load_cli', return_value=cli), patch.object(sys, 'argv', ['adapter'] + argv), contextlib.redirect_stdout(output):
            code = adapter.main()
        return code, json.loads(output.getvalue())

    def test_launch_failure_preserves_created_instance_and_uses_existing_command(self):
        record = dict(instance_id='ocid1.instance.example', name='qbot', region='us-chicago-1', progress='ssh-verification-failed', ssh=dict(username='ubuntu', private_key='/Users/test/.ssh/key'))
        calls = []
        cli = self.cli

        class Store:
            def lock(self):
                return contextlib.nullcontext()

            def records(self):
                return [record]

        class Manager:
            def __init__(self, *_):
                pass

            def command(self, args):
                calls.append((args.command, args.config))
                raise cli.Error('Instance created, but SSH verification failed')

            def resolve(self, *_):
                shape = SimpleNamespace(ocpus=2, memory_in_gbs=8)
                instance = SimpleNamespace(display_name='qbot', lifecycle_state='RUNNING', availability_domain='AD-1', shape='VM.Standard.A1.Flex', shape_config=shape,
                    time_created=datetime(2026, 10, 11, 19, 0, tzinfo=timezone(timedelta(hours=-5))))
                return record, {}, instance

            def addresses(self, *_):
                return [dict(public_ipv4='203.0.113.7')]

        with patch.object(cli, 'Store', Store), patch.object(cli, 'Manager', Manager), patch.object(cli, 'auth_config', return_value={}):
            code, result = self.run_adapter(['launch', '-c', '/existing.yml'], cli)
        self.assertEqual(calls, [('launch', '/existing.yml')])
        self.assertEqual(code, 1)
        self.assertFalse(result['ok'])
        self.assertEqual(result['instances'][0]['state'], 'RUNNING')
        self.assertEqual(result['instances'][0]['instance_id'], record['instance_id'])
        self.assertEqual(result['instances'][0]['ocpus'], 2)
        self.assertEqual(result['instances'][0]['time_created'], '2026-10-12T00:00:00+00:00')
        self.assertIsNone(adapter.utc_timestamp(None))
        self.assertEqual(result['instances'][0]['ssh']['private_key'], '/Users/test/.ssh/key')

    def test_real_parser_requires_one_boot_volume_choice(self):
        for flag, preserve in [('--preserve-boot-volume', True), ('--delete-boot-volume', False)]:
            args = self.cli.parser().parse_args(['terminate', 'ocid1.instance.example', '--region', 'us-chicago-1', flag])
            self.assertEqual(args.preserve_boot_volume, preserve)
            self.assertFalse(args.cleanup_network)
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            self.cli.parser().parse_args(['terminate', 'ocid1.instance.example'])
        # The real YAML loader is exercised without credentials or cloud access.
        example = self.cli.ROOT / 'config/oci-qbot.example.yml'
        content = example.read_text().replace('ocid1.tenancy.oc1..REPLACE_WITH_QENDRO77_ROOT_OCID', 'ocid1.tenancy.oc1..example')
        with tempfile.TemporaryDirectory() as directory:
            filename = Path(directory) / 'oci.yml'
            filename.write_text(content)
            code, result = self.run_adapter(['summary', '-c', str(filename)], self.cli)
        self.assertEqual(code, 0)
        self.assertEqual(result['summary']['mode'], 'free-only')
        self.assertTrue(result['summary']['ssh']['private_key'].startswith('/'))
        self.assertNotIn('public_key', result['summary']['ssh'])


if __name__ == '__main__':
    unittest.main()

"""Tests of the common pack generator. Standard library only (unittest); pytest runs them too.

Run:  python test_gen_common.py
Needs the speed-merchants repo beside ai-setup (or PACKGEN_TOOLS = <speed-merchants>\\CrewChief\\packs\\tools) and pwsh.
"""
import glob
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.environ.get('PACKGEN_TOOLS') or os.path.abspath(
    os.path.join(HERE, '..', '..', '..', '..', 'speed-merchants', 'CrewChief', 'packs', 'tools'))
sys.path.insert(0, TOOLS)
from packgen.testing import run_ps  # noqa: E402

NAMES = {'common-api-key-set', 'common-base-backup-check', 'common-health-wait', 'common-instance-pools',
         'common-instance-start', 'common-instance-stop', 'common-testauto-tag-check'}
DEFAULTED = {'PoolAction': 'Recycle', 'AllowNone': 'false', 'ProfiseeApiKey': '{{$config:RestKeys:ProfiseeRestKey}}'}


class CommonPack(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._tmp = tempfile.TemporaryDirectory()
        cls.root = os.path.join(cls._tmp.name, 'common')
        done = subprocess.run([sys.executable, os.path.join(HERE, 'gen_common.py'), cls.root], capture_output=True, text=True,
                              env=dict(os.environ, PACKGEN_TOOLS=TOOLS))
        if done.returncode != 0:
            raise RuntimeError(done.stderr)
        cls.workloads = {}
        for path in glob.glob(os.path.join(cls.root, 'workloads', 'common', 'internal', '*.workload.json')):
            with open(path, encoding='utf-8') as f:
                w = json.load(f)
            cls.workloads[w['name']] = w

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def test_workload_names(self):
        self.assertEqual(NAMES, set(self.workloads))

    def test_no_reference_data_and_no_box_value(self):
        self.assertFalse(os.path.exists(os.path.join(self.root, 'reference-kv')))
        for w in self.workloads.values():
            self.assertNotIn('$ref:', json.dumps(w), w['name'])
            for name, value in w['globalParameters'].items():
                self.assertTrue(value == '' or value.startswith('{{$config:'), '%s global %s' % (w['name'], name))

    def test_inputs_are_described_and_have_no_default(self):
        for w in self.workloads.values():
            self.assertTrue(w.get('inputs'), w['name'])
            for i in w['inputs']:
                self.assertTrue(i['description'], '%s input %s' % (w['name'], i['name']))
                if i['name'] in DEFAULTED:
                    self.assertEqual(DEFAULTED[i['name']], i['default'])
                else:
                    self.assertNotIn('default', i, '%s input %s' % (w['name'], i['name']))

    def test_api_key_is_set_in_one_place(self):
        holders = [w['name'] for w in self.workloads.values() if any(s['inline']['type'] == 'SetApiKeyStep' for s in w['steps'])]
        self.assertEqual(['common-api-key-set'], holders)
        labels = [s['label'] for s in self.workloads['common-api-key-set']['steps']]
        self.assertEqual(['Stop The Instance', 'Set API Key', 'Start The Instance', 'Wait For Every Service',
                          'Verify API Key Through Gateway', 'Verify API Key Through Data Service'], labels)

    def tag_script(self):
        return self.workloads['common-testauto-tag-check']['steps'][0]['inline']['scriptContent']

    def test_tag_check_trims_items_and_skips_blanks(self):
        # Review focus 3: "a, b,," is a and b.
        self.assertIn("-split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique", self.tag_script())

    def test_tag_check_empty_list_fails_before_any_call(self):
        code, _out, err = run_ps(self.tag_script(), {'{{TagKeys}}': ' , ', '{{TestAutoBaseUrl}}': 'https://127.0.0.1:1',
                                                     '{{ProfiseeVersionCode}}': 'V', '{{SetupName}}': 'demo-setup', '{{AllowNone}}': 'false'})
        self.assertNotEqual(0, code)
        self.assertIn('TagKeys is empty', err)

    def test_tag_check_missing_key_message_names_the_setup(self):
        # Review focus 4: the message says which workload to run, not "No TestAuto workflow carries tag".
        script = self.tag_script()
        self.assertIn('Run $setup', script)
        self.assertIn("do not exist for this box and version", script)

    def test_service_is_found_never_named(self):
        for name in ('common-instance-stop', 'common-instance-start'):
            w = self.workloads[name]
            labels = [s['label'] for s in w['steps']]
            self.assertLess(labels.index('Find The Instance Service'), labels.index(next(l for l in labels if 'Profisee Service' in l)))
            self.assertEqual('', w['globalParameters']['InstanceServiceName'])

    # ---------------------------------------------------------------- common-health-wait heals itself
    HEALTH_URL = 'http://127.0.0.1:%d/demo/rest'

    def health_step(self, label):
        return next(s for s in self.workloads['common-health-wait']['steps'] if s['label'] == label)['inline']

    def run_health(self, label, url, minutes=None):
        script = self.health_step(label)['scriptContent']
        if minutes is not None:
            first, rest = script.split('\r\n', 2)[1], None
            self.assertTrue(first.startswith('$Minutes = '), first)
            script = script.replace(first, '$Minutes = %s' % minutes, 1)
        return run_ps(script, {'{{ProfiseeBaseUrl}}': url})

    @staticmethod
    def serve(body):
        """A local stand-in for the health address (synthetic answers); returns (server, port)."""
        import http.server
        import threading

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                data = body.encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        return server, server.server_address[1]

    def test_health_wait_steps_restart_once_only_when_still_not_healthy(self):
        w = self.workloads['common-health-wait']
        self.assertEqual(['Wait For Every Service', 'Name The Server To Restart', 'Name The Instance To Restart',
                          'Stop The Instance', 'Start The Instance', 'Wait Again After The Restart'], [s['label'] for s in w['steps']])
        self.assertEqual({'RestartServerName': '', 'RestartInstanceName': ''}, w['globalParameters'])
        self.assertEqual(['ProfiseeBaseUrl'], [i['name'] for i in w['inputs']], 'no caller has to pass anything new')
        self.assertIsNone(self.health_step('Wait For Every Service').get('runWhen'))
        self.assertIsNone(self.health_step('Name The Server To Restart').get('runWhen'))
        self.assertEqual('RestartServerName', self.health_step('Name The Server To Restart')['outputParameterName'])
        self.assertEqual('RestartInstanceName', self.health_step('Name The Instance To Restart')['outputParameterName'])
        for label in ('Name The Instance To Restart', 'Stop The Instance', 'Start The Instance', 'Wait Again After The Restart'):
            self.assertEqual('{{RestartServerName}}', self.health_step(label)['runWhen'], label)
        for label, child in (('Stop The Instance', 'common-instance-stop'), ('Start The Instance', 'common-instance-start')):
            step = self.health_step(label)
            self.assertEqual(child, step['workloadName'], 'the tested stop and start are reused, not copied')
            self.assertEqual({'ApplicationServerName': '{{RestartServerName}}', 'ProfiseeInstanceName': '{{RestartInstanceName}}'},
                             step['parameters'], 'the server and instance come from the address that was asked, never from the caller')
        total = sum(self.health_step(l)['timeoutSeconds'] for l in ('Wait For Every Service', 'Wait Again After The Restart'))
        self.assertLessEqual(total, 1000, 'callers give this workload 1200 seconds')

    def test_health_all_healthy_ends_at_once_and_names_no_server(self):
        server, port = self.serve('{"healthChecks":{"Data":{"status":"Healthy"},"Matching":{"status":"Healthy"}}}')
        try:
            url = self.HEALTH_URL % port
            code, out, err = self.run_health('Wait For Every Service', url)
            self.assertEqual(0, code, err)
            self.assertIn('All 2 health checks Healthy', out)
            code, out, err = self.run_health('Name The Server To Restart', url)
            self.assertEqual(0, code, err)
            self.assertEqual('', out.strip(), 'blank = nothing is restarted')
        finally:
            server.shutdown()

    def test_health_still_down_first_wait_ends_green_and_the_server_is_named(self):
        server, port = self.serve('{"healthChecks":{"Data":{"status":"Healthy"},"Matching":{"status":"Unhealthy"}}}')
        try:
            url = self.HEALTH_URL % port
            code, out, err = self.run_health('Wait For Every Service', url, minutes=0)
            self.assertEqual(0, code, 'the first wait never fails: the restart comes next. ' + err)
            self.assertIn('Not healthy yet: Matching', out)
            self.assertIn('restarted once', out)
            code, out, err = self.run_health('Name The Server To Restart', url)
            self.assertEqual(0, code, err)
            self.assertEqual('127.0.0.1', out.strip(), 'only the name: it becomes a run value')
            code, out, err = self.run_health('Wait Again After The Restart', url, minutes=0)
            self.assertNotEqual(0, code, 'after the restart a service that stays down is a failure')
            self.assertIn('still not healthy', err)
            self.assertIn('Matching', err)
            self.assertIn('after one restart', err)
        finally:
            server.shutdown()

    def test_health_server_and_instance_come_from_the_address(self):
        # A name that does not resolve: the probe fails, so the server is named; its short name is the first label.
        url = 'https://app-x.invalid/demo/rest'
        code, out, err = self.run_health('Name The Server To Restart', url)
        self.assertEqual(0, code, err)
        self.assertEqual('app-x', out.strip())
        code, out, err = self.run_health('Name The Instance To Restart', url)
        self.assertEqual(0, code, err)
        self.assertEqual('demo', out.strip())

    def test_health_address_without_an_instance_is_refused_not_guessed(self):
        code, _out, err = self.run_health('Name The Instance To Restart', 'https://app-x.invalid/rest')
        self.assertNotEqual(0, code)
        self.assertIn('cannot tell the instance', err)


if __name__ == '__main__':
    unittest.main()

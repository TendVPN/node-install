import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('guard', Path(__file__).resolve().parents[1] / 'src/guard.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)

class GuardTests(unittest.TestCase):
    def test_local_http_serves_filtered_list(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'filtered'
            path.write_text('203.0.113.0/24\n2001:db8::/32\n')
            client = Path(directory) / 'client.py'
            client.write_text('import sys,urllib.request\nassert sys.argv[1:3] == ["full", "-u"]\nassert sys.argv[3].startswith("http://127.0.0.1:")\nassert urllib.request.urlopen(sys.argv[3]).read() == b"203.0.113.0/24\\n2001:db8::/32\\n"\n')
            guard.apply_list(path, (sys.executable, str(client)))

    def test_false_success_and_failure_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'filtered'
            path.write_text('203.0.113.0/24\n')
            with self.assertRaises(ValueError):
                guard.apply_list(path, (sys.executable, '-c', 'pass'))
            with self.assertRaises(subprocess.CalledProcessError):
                guard.apply_list(path, (sys.executable, '-c', 'raise SystemExit(3)'))
            path.write_text('')
            with self.assertRaises(ValueError):
                guard.apply_list(path)

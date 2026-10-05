import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('compose', Path(__file__).resolve().parents[1] / 'src/compose.py')
compose = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compose)

class ComposeTests(unittest.TestCase):
    def test_mount_is_node_only_idempotent_and_backed_up(self):
        original = '''services:
  remnawave-nginx:
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
  remnanode:
    environment:
      - SECRET_KEY=TEST_SECRET
    volumes:
      - /dev/shm:/dev/shm:rw
  other:
    image: example
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'docker-compose.yml'
            path.write_text(original)
            path.chmod(0o600)
            self.assertTrue(compose.add_certificate_mount(path))
            updated = path.read_text()
            self.assertIn('    volumes:\n      - /etc/letsencrypt:/etc/letsencrypt:ro\n      - /dev/shm', updated)
            self.assertNotIn('/etc/letsencrypt', updated.split('  remnanode:')[0])
            self.assertIn('SECRET_KEY=TEST_SECRET', updated)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(path.with_name(path.name + '.before-certificates').read_text(), original)
            self.assertFalse(compose.add_certificate_mount(path))
            self.assertEqual(path.read_text(), updated)

    def test_unrecognized_compose_is_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'docker-compose.yml'
            original = 'services:\n  remnanode:\n    image: remnawave/node:latest\n'
            path.write_text(original)
            with self.assertRaises(ValueError):
                compose.add_certificate_mount(path)
            self.assertEqual(path.read_text(), original)

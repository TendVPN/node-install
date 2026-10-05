import subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class SSHSetupTests(unittest.TestCase):
 def test_runtime_directory_and_restore_on_validation_failure(self):
  with tempfile.TemporaryDirectory() as d:
   base=Path(d);ssh=base/'etc/ssh';drop=ssh/'sshd_config.d';drop.mkdir(parents=True)
   original='Include /etc/ssh/sshd_config.d/*.conf\nPort 22\n'
   (ssh/'sshd_config').write_text(original);(drop/'provider.conf').write_text('Port 22\nPasswordAuthentication yes\n')
   (drop/'00-tend-port.conf').write_text('Port 2200\n')
   stub=base/'sshd';stub.write_text('#!/bin/sh\n[ -d "'+d+'/run/sshd" ] || exit 99\necho checked-runtime >&2\nexit 1\n');stub.chmod(0o755)
   source=(ROOT/'src/server.sh').read_text().split('setup_ssh() {',1)[1].split('\nconfirm_ssh()',1)[0]
   source='setup_ssh() {'+source
   for path in ['/var/lib/tend','/etc/ssh','/run/sshd']:
    source=source.replace(path,d+path)
   source=source.replace('/usr/sbin/sshd',str(stub)).replace('-o root -g root ', '')
   script='set -eu\nui_action() { :; }\ndeclare -A C=([ssh_port]=22223)\nfail() { echo "$*" >&2; exit 1; }\n'+source+'\nsetup_ssh\n'
   r=subprocess.run(['bash','-c',script],capture_output=True,text=True)
   self.assertNotEqual(r.returncode,0);self.assertIn('checked-runtime',r.stderr)
   self.assertEqual((ssh/'sshd_config').read_text(),original)
   self.assertEqual((drop/'provider.conf').read_text(),'Port 22\nPasswordAuthentication yes\n')
   self.assertEqual((drop/'00-tend-port.conf').read_text(),'Port 2200\n')
   self.assertEqual((base/'run/sshd').stat().st_mode&0o777,0o755)

 def test_password_auth_disabled_and_restored_on_failure(self):
  with tempfile.TemporaryDirectory() as d:
   base=Path(d);ssh=base/'etc/ssh';drop=ssh/'sshd_config.d';drop.mkdir(parents=True)
   original='PasswordAuthentication yes\nInclude '+str(drop)+'/*.conf\nMatch User root\n  PasswordAuthentication yes\n'
   provider='KbdInteractiveAuthentication yes\nChallengeResponseAuthentication yes\n'
   (ssh/'sshd_config').write_text(original);(drop/'provider.conf').write_text(provider)
   subprocess.run(['ssh-keygen','-q','-t','ed25519','-N','','-f',str(base/'hostkey')],check=True)
   stub=base/'sshd'
   stub.write_text('#!/bin/sh\n/usr/bin/sshd -T -h "'+str(base/'hostkey')+'" -f "'+str(ssh/'sshd_config')+'" -C user=root,host=localhost,addr=127.0.0.1 > "'+d+'/effective"\nexit 1\n');stub.chmod(0o755)
   source='setup_ssh() {'+(ROOT/'src/server.sh').read_text().split('setup_ssh() {',1)[1].split('\nconfirm_ssh()',1)[0]
   for path in ['/var/lib/tend','/etc/ssh','/run/sshd']: source=source.replace(path,d+path)
   source=source.replace('/usr/sbin/sshd',str(stub)).replace('-o root -g root ', '')
   script='set -eu\nui_action() { :; }\ndeclare -A C=([ssh_port]=22223 [disable_password_auth]=yes)\nfail() { exit 1; }\n'+source+'\nsetup_ssh'
   r=subprocess.run(['bash','-c',script],capture_output=True,text=True)
   self.assertNotEqual(r.returncode,0)
   effective=(base/'effective').read_text().lower()
   self.assertIn('passwordauthentication no',effective,r.stderr)
   self.assertIn('kbdinteractiveauthentication no',effective,r.stderr)
   self.assertEqual((ssh/'sshd_config').read_text(),original)
   self.assertEqual((drop/'provider.conf').read_text(),provider)

 def test_confirm_requires_connection_before_disarming_timer(self):
  source=(ROOT/'src/server.sh').read_text().split('confirm_ssh() {',1)[1].split('\nservice_tcp_ports()',1)[0]
  script='set -eu\nrequire_server() { :; }\nfail() { echo "$*" >&2; exit 1; }\nsystemctl() { echo unexpected-systemctl; }\nunset SSH_CONNECTION\nconfirm_ssh() {'+source+'\nconfirm_ssh'
  r=subprocess.run(['bash','-c',script],capture_output=True,text=True)
  self.assertNotEqual(r.returncode,0);self.assertIn('--preserve-env=SSH_CONNECTION',r.stderr)
  self.assertNotIn('unexpected-systemctl',r.stdout)

 def test_missing_firewall_reports_ssh_confirmed(self):
  source=(ROOT/'src/server.sh').read_text().split('confirm_ssh() {',1)[1].split('\nservice_tcp_ports()',1)[0]
  script='set -eu\ndeclare -A C=([ssh_port]=22223 [protect]=yes)\nSSH_CONNECTION="203.0.113.1 5555 203.0.113.2 22223"\nrequire_server() { :; }\nui_action() { shift; echo "$*"; }\nfail() { echo "$*" >&2; exit 1; }\nsystemctl() { echo "systemctl $*"; }\nnft() { return 1; }\nconfirm_ssh() {'+source+'\nconfirm_ssh'
  r=subprocess.run(['bash','-c',script],capture_output=True,text=True)
  self.assertNotEqual(r.returncode,0);self.assertIn('SSH подтверждён',r.stdout)
  self.assertIn('tend-menu',r.stderr);self.assertNotIn('stop na-fw-safety.timer',r.stdout)

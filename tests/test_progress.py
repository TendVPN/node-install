import os,pty,select,subprocess,tempfile,time,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class ProgressTests(unittest.TestCase):
 def test_output_logged_and_failure_propagates(self):
  for success in [True,False]:
   with tempfile.TemporaryDirectory() as d:
    log=Path(d)/'run.log'
    script='source "$1"; TEND_LOGFILE=$2; work() { echo PRIVATE_OUTPUT; '+('true' if success else 'false; echo SHOULD_NOT_RUN')+'; }; ui_step "Тест" work || exit $?'
    r=subprocess.run(['bash','-c',script,'test',str(ROOT/'src/ui.sh'),str(log)],capture_output=True,text=True)
    self.assertEqual(r.returncode,0 if success else 1,r.stderr)
    self.assertNotIn('PRIVATE_OUTPUT',r.stdout+r.stderr);self.assertIn('PRIVATE_OUTPUT',log.read_text())
    self.assertNotIn('SHOULD_NOT_RUN',log.read_text());self.assertIn('[Tend-Menu]:',r.stdout)
    if not success:self.assertIn(str(log),r.stderr)
 def test_animation_in_terminal(self):
  with tempfile.TemporaryDirectory() as d:
   pid,fd=pty.fork()
   if pid==0:
    os.environ['TERM']='xterm'
    os.execvp('bash',['bash','-c','source "$1"; TEND_LOGFILE=$2; ui_step "Ожидание" sleep 0.4','test',str(ROOT/'src/ui.sh'),d+'/run.log'])
   output=b''
   try:
    while select.select([fd],[],[],3)[0]:
     try:part=os.read(fd,65536)
     except OSError:break
     if not part:break
     output+=part
    _,status=os.waitpid(pid,0)
   finally:os.close(fd)
   text=output.decode();self.assertEqual(os.waitstatus_to_exitcode(status),0,text)
   self.assertIn('⠋',text);self.assertIn('готово',text)

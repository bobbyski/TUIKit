# A CHATTY fake VectorTerminal: answers probes, then fires frameStarted /
# frameCommitted APC replies at every VTG frame command — sometimes split
# at hostile byte boundaries (ESC at the end of one chunk, the backslash in
# the next) — plus unsolicited resize-style replies. Then ^Q.
import os, pty, select, subprocess, sys, time

binary = sys.argv[1]
controller, follower = pty.openpty()
child = subprocess.Popen([binary], stdin=follower, stdout=follower, stderr=follower, close_fds=True)
os.close(follower)

output = b''
answered_caps = answered_glyph = False
frames_seen = 0
replies = 0

def reply(payload, split):
    global replies
    data = b'\x1b_VTG;' + payload + b'\x1b\\'
    if split:
        # End the first chunk ON the ESC of ST — the nastiest boundary.
        os.write(controller, data[:-1])
        time.sleep(0.005)
        os.write(controller, data[-1:])
    else:
        os.write(controller, data)
    replies += 1

def pump(timeout):
    global output, answered_caps, answered_glyph, frames_seen
    r, _, _ = select.select([controller], [], [], timeout)
    if controller in r:
        try:
            chunk = os.read(controller, 65536)
        except OSError:
            return
        before = output
        output += chunk
        if not answered_caps and b'capabilities?' in output:
            reply(b'capabilities,protocol=VTG,version=1', False)
            answered_caps = True
        if not answered_glyph and b'glyphSize?' in output:
            os.write(controller, b'\x1b_VTG;glyphSize,character=W,width=9.5,height=20\x1b\\')
            answered_glyph = True
        new_frames = chunk.count(b'frame,') + chunk.count(b'startFrame') + chunk.count(b'endFrame')
        for i in range(new_frames):
            frames_seen += 1
            reply(b'frameStarted,id=tuikit-chrome,timeout=250', frames_seen % 2 == 0)
            reply(b'frameCommitted,id=tuikit-chrome', frames_seen % 3 == 0)

deadline = time.time() + 4
while time.time() < deadline:
    pump(0.05)

print(f'frames seen: {frames_seen}, replies sent: {replies}', flush=True)

# Poke the app so more frames flow (mouse moves force redraw paths), with
# replies interleaving, then quit.
for i in range(5):
    os.write(controller, b'\t')   # tab: refocus, dirty, present
    t = time.time() + 0.3
    while time.time() < t:
        pump(0.05)

os.write(controller, b'\x11')
print('sent ^Q', flush=True)

deadline = time.time() + 6
while time.time() < deadline and child.poll() is None:
    pump(0.2)

code = child.poll()
if code is None:
    print('STILL RUNNING after ^Q — REPRODUCED', flush=True)
    os.system(f"sample {child.pid} 3 -file stop-sample.txt >/dev/null 2>&1")
    child.kill()
else:
    print(f'exited with {code}', flush=True)

print('---tail---')
print(output[-200:].decode('utf-8', 'replace'))

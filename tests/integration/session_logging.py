"""Check the installed session loggers in a disposable Podman container."""

import concurrent.futures
import json
import os
import pathlib
import socket
import subprocess
import sys
import unittest


sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from test_boot import greeter_command, session_command


PAYLOAD = '''import json, os, sys
print(json.dumps({"argv": sys.argv[1:], "stdin": sys.stdin.read(),
                  "environment": os.environ["MANDARA_LOG_TEST"],
                  "pid": os.getpid()}), flush=True)
print("session diagnostic", file=sys.stderr, flush=True)
sys.exit(int(os.environ["MANDARA_LOG_EXIT"]))
'''


class SessionLoggingTests(unittest.TestCase):
    def test_output_reaches_journal_without_changing_the_session(self):
        if os.getuid() != 0 or not pathlib.Path("/run/.containerenv").exists():
            self.fail("run this integration test inside a disposable Podman container")
        endpoint = pathlib.Path("/run/systemd/journal/stdout")
        self.assertFalse(endpoint.exists(), "the container must not run a journal daemon")
        endpoint.parent.mkdir(parents=True, exist_ok=True)

        for command in (greeter_command(pathlib.Path("/")), session_command(pathlib.Path("/"))):
            for exit_code in (0, 17):
                with self.subTest(command=command, exit_code=exit_code):
                    # A private journal stream peer receives the real systemd-cat
                    # handshake and bytes; the host journal is never contacted.
                    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
                        listener.bind(str(endpoint))
                        listener.listen(1)
                        listener.settimeout(5)

                        def receive():
                            connection, _ = listener.accept()
                            with connection:
                                connection.settimeout(5)
                                chunks = []
                                while chunk := connection.recv(4096):
                                    chunks.append(chunk)
                                return b"".join(chunks).decode()

                        try:
                            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as worker:
                                journal = worker.submit(receive)
                                # Substitute a diagnostic child for cage/Mango;
                                # retain the installed journal command and options.
                                with subprocess.Popen(
                                    command[:2] + [sys.executable, "-c", PAYLOAD, "two words", ""],
                                    stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, text=True,
                                    env=os.environ | {
                                        "MANDARA_LOG_TEST": "inherited",
                                        "MANDARA_LOG_EXIT": str(exit_code),
                                    },
                                ) as process:
                                    stdout, stderr = process.communicate("session input", timeout=10)
                                    self.assertEqual(process.returncode, exit_code)
                                    self.assertEqual(stdout, "")
                                    self.assertEqual(stderr, "")
                                    messages = journal.result(timeout=5)
                                    record = json.loads(next(
                                        line for line in messages.splitlines() if line.startswith("{")
                                    ))
                                    self.assertEqual(record["pid"], process.pid)
                                    self.assertEqual(record["argv"], ["two words", ""])
                                    self.assertEqual(record["stdin"], "session input")
                                    self.assertEqual(record["environment"], "inherited")
                                    self.assertIn("session diagnostic", messages)
                                    self.assertIn(command[1].split("=", 1)[1], messages)
                        finally:
                            endpoint.unlink()


if __name__ == "__main__":
    unittest.main()

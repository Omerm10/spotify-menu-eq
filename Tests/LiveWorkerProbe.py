#!/usr/bin/env python3
"""Opt-in live test. Spotify must already be playing; this briefly processes its audio."""
import argparse
import json
import os
from pathlib import Path
import selectors
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cycles', type=int, default=3)
    parser.add_argument('--seconds', type=float, default=5)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if not 1 <= args.cycles <= 100 or not 1 <= args.seconds <= 3600:
        parser.error('cycles must be 1..100 and seconds must be 1..3600')
    executable = Path(__file__).resolve().parent.parent / 'Spotify Menu EQ.app/Contents/MacOS/SpotifyMenuEQ'
    results = []
    for cycle in range(args.cycles):
        started = time.monotonic()
        child = subprocess.Popen([str(executable), '--eq-helper', str(os.getpid()), '0', '0', '0', '0', '0'],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 text=True, bufsize=1)
        selector = selectors.DefaultSelector()
        selector.register(child.stdout, selectors.EVENT_READ)
        selector.register(child.stderr, selectors.EVENT_READ)
        ready = None
        health = []
        messages = []
        applied = 0
        next_change = 0
        try:
            while time.monotonic() - started < 25 + args.seconds:
                for key, _ in selector.select(0.2):
                    line = key.fileobj.readline().strip()
                    if not line:
                        selector.unregister(key.fileobj)
                        continue
                    if line == 'READY':
                        ready = time.monotonic() - started
                    if line.startswith('APPLIED '):
                        applied += 1
                    if line.startswith('HEALTH '):
                        health.append(line)
                    else:
                        messages.append(line)
                        if line.startswith(('STAGE ', 'ERROR ')):
                            print(f'cycle={cycle + 1} {line}', flush=True)
                elapsed = time.monotonic() - started
                if ready is not None:
                    if elapsed - ready > args.seconds:
                        break
                    if elapsed >= next_change:
                        preset = 'SET 5 2 -2 0 0\n' if applied % 2 else 'SET 0 0 0 0 0\n'
                        child.stdin.write(preset)
                        child.stdin.flush()
                        next_change = elapsed + 10
                elif elapsed > 25:
                    break
                if child.poll() is not None:
                    break
            child.stdin.close()
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
            result = dict(cycle=cycle + 1, ready_seconds=ready, exit=child.returncode,
                          applied_configurations=applied, health_samples=len(health),
                          last_health=health[-1] if health else None, messages=messages)
            results.append(result)
            print(json.dumps({key: value for key, value in result.items() if key != 'messages'}), flush=True)
            if ready is None:
                break
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
            selector.close()
            child.stdout.close()
            child.stderr.close()
    if args.report:
        args.report.write_text(json.dumps(results, indent=2) + '\n')
    def passed(result):
        if result['ready_seconds'] is None or result['exit'] != 0 or not result['last_health']:
            return False
        metrics = dict(field.split('=', 1) for field in result['last_health'].split()[1:] if '=' in field)
        counters = ('overflowFrames', 'underrunFrames', 'invalidBuffers', 'nonfiniteSamples', 'clippedOutputSamples')
        return all(metrics.get(key) == '0' for key in counters)
    return 0 if len(results) == args.cycles and all(passed(result) for result in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())

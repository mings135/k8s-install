#!/usr/bin/env python3
# -*- coding:utf-8 -*-

'''
Author: MingQ
用途: 同时在多个远程主机上执行命令, 并实时输出stdout(必须先做免密)
'''

import threading, sys
from subprocess import Popen, PIPE


class RunCommandThread(threading.Thread):
    def __init__(self, cmd, lock):
        super().__init__()
        self.cmd = cmd
        self.lock = lock
        self.result = 0

    def run(self) -> None:
        pipe = Popen(self.cmd, stdout=PIPE, shell=True)
        while True:
            line = pipe.stdout.readline()
            if line:
                with self.lock:
                    print(line.decode('utf-8'), end='')
            else:
                break
        self.result = pipe.wait()
        pipe.stdout.close()


def main():
    lock = threading.Lock()
    run_user = sys.argv[1]
    run_command = sys.argv[2]
    remote_ips = sys.argv[3:]
    remote_runs = []
    results_code = 0
    for ip in remote_ips:
        cmd = 'ssh %s@%s %s' % (run_user, ip, run_command)
        rct = RunCommandThread(cmd, lock)
        rct.start()
        remote_runs.append(rct)

    for rct in remote_runs:
        rct.join()
        results_code += rct.result

    if results_code > 0:
        sys.exit(1)

if __name__ == '__main__':
    main()
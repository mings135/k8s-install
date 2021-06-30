#!/usr/bin/env python3
# -*- coding:utf-8 -*-

'''
多线程并发执行远程脚本
'''

import threading, sys
from subprocess import Popen, PIPE


class RunCommandThread(threading.Thread):

    def __init__(self, cmd):
        super().__init__()
        self.cmd = cmd

    def run(self) -> None:
        pipe = Popen(self.cmd, stdout=PIPE, shell=True)
        while True:
            line = pipe.stdout.readline()
            if line:
                print(line.decode('utf-8'), end='')
            else:
                break
        pipe.wait()
        pipe.stdout.close()


def main():
    run_command = sys.argv[1]
    remote_ips = sys.argv[2:]
    remote_runs = []
    for ip in remote_ips:
        cmd = 'ssh root@%s %s' % (ip, run_command)
        rct = RunCommandThread(cmd)
        rct.start()
        remote_runs.append(rct)

    for rct in remote_runs:
        rct.join()


if __name__ == '__main__':
    main()
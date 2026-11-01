#!/usr/bin/env python3
"""Build the native installer and test official archive layout, checksums and immutable installs.

Requires a built sibling ../Tallow checkout, or --engine PATH. Uses only a local HTTP server.
"""
import argparse
import functools
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import tomllib
import zipfile

PROGRAM = r'''using System;
using Tallow;
namespace TallowManager;
class Program {
    public static int Main(String[] args) {
        let task = scope Task("Test install", "tallow", new (task) => true);
        let release = scope Release();
        release.tag.Set("build-test");
        release.assetUrl.Set(args[0]);
        release.sumsUrl.Set(args[1]);
        let ok = EngineInstall.Install(task, release, "Tallow-Linux.zip", args[2]);
        let error = scope String();
        task.GetError(error);
        Console.WriteLine(scope $"installed={ok}: {error}");
        return ok ? 0 : 1;
    }
}
'''


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, default=root.parent / 'Tallow')
    args = parser.parse_args()
    engine = args.engine.resolve()
    with tempfile.TemporaryDirectory(prefix='tallow-install-test-') as temporary:
        work = Path(temporary)
        source = work / 'src'
        shutil.copytree(root / 'src', source)
        (source / 'Program.bf').write_text(PROGRAM)
        proj = tomllib.loads((root / 'BeefProj.toml').read_text())
        flags = proj['Configs']['Debug']['Linux64']['OtherLinkFlags'].replace('$(WorkspaceDir)/../Tallow', str(engine))
        (work / 'BeefSpace.toml').write_text('FileVersion = 1\nProjects = {TallowManager = {Path = "."}, Tallow = {Path = ' + json.dumps(str(engine / 'Engine')) + '}}\n[Workspace]\nStartupProject = "TallowManager"\n')
        (work / 'BeefProj.toml').write_text('FileVersion = 1\nDependencies = {corlib = "*", Tallow = "*"}\n[Project]\nName = "TallowManager"\nTargetType = "BeefConsoleApplication"\nStartupObject = "TallowManager.Program"\n[Configs.Debug.Linux64]\nOtherLinkFlags = ' + json.dumps(flags) + '\n')
        subprocess.run([os.environ.get('BEEFBUILD', 'BeefBuild'), f'-workspace={work}', '-config=Debug', '-verbosity=minimal'], check=True, stdout=subprocess.DEVNULL)
        web = work / 'web'
        web.mkdir()
        archive = web / 'Tallow-Linux.zip'
        data = {'engine': 'Tallow', 'version': 'build-test', 'build': 'a' * 40, 'project_format': 1}
        with zipfile.ZipFile(archive, 'w') as out:
            out.writestr('Tallow-Linux/tallow-version.json', json.dumps(data))
            out.writestr('Tallow-Linux/Engine/', '')
            out.writestr('Tallow-Linux/Editor/', '')
        (web / 'SHA256SUMS.txt').write_text(hashlib.sha256(archive.read_bytes()).hexdigest() + '  Tallow-Linux.zip\n')
        (web / 'bad-sums.txt').write_text('0' * 64 + '  Tallow-Linux.zip\n')
        server = ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(SimpleHTTPRequestHandler, directory=web))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base = f'http://127.0.0.1:{server.server_port}'
            executable = work / 'build/Debug_Linux64/TallowManager/TallowManager'
            installed = work / 'installed'
            def install(sums, destination):
                result = subprocess.run([str(executable), base + '/Tallow-Linux.zip', base + '/' + sums, str(destination)], capture_output=True, text=True, timeout=60)
                print(result.stdout.strip())
                assert not list(destination.glob('.installing-*')), 'Staging folders were not cleaned up'
                return result.returncode
            assert install('SHA256SUMS.txt', installed) == 0
            manifest = installed / 'versions/build-test' / ('a' * 40) / 'tallow-version.json'
            assert json.loads(manifest.read_text()) == data
            assert install('SHA256SUMS.txt', installed) != 0
            assert json.loads(manifest.read_text()) == data
            assert install('bad-sums.txt', work / 'rejected') != 0
            assert not (work / 'rejected/versions').exists()
            print('PASS: platform-folder archive installation, immutable reinstall rejection, checksum rejection, and staging cleanup')
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == '__main__':
    main()

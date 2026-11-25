#!/usr/bin/env python3
"""
Deploy Chomp Wars to a Batocera machine as a Steam system game.

Prompts interactively for the Batocera host and credentials (no defaults hardcoded).
Copies the game, sets up the Godot runtime, exports the game package, installs
the EmulationStation Steam launcher and padtokey hotkeys, adds artwork, and
registers the game in Steam Big Picture.
"""

import sys
import os
import getpass
import argparse
import atexit
import shutil
import tempfile
import pty
import select
import time
import fcntl
import termios
from pathlib import Path


def run_ssh_or_scp(cmd_args, password="", timeout=300, verbose=True):
    """
    Run ssh or scp inside a pseudo-terminal (PTY) to seamlessly handle
    password prompts without requiring external dependencies like sshpass.
    """
    master, slave = pty.openpty()
    pid = os.fork()

    if pid == 0:
        os.close(master)
        os.setsid()
        try:
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        except Exception:
            pass
        os.dup2(slave, 0)
        os.dup2(slave, 1)
        os.dup2(slave, 2)
        os.close(slave)
        os.execvp(cmd_args[0], cmd_args)
    else:
        os.close(slave)
        output = b""
        start_time = time.time()
        pass_sent = False

        while time.time() - start_time < timeout:
            r, _, _ = select.select([master], [], [], 0.5)
            if r:
                try:
                    chunk = os.read(master, 4096)
                    if not chunk:
                        break
                    output += chunk
                    text = chunk.decode("utf-8", errors="replace")

                    # Avoid echoing the password prompt if we're auto-filling it
                    if b"password:" in chunk.lower() and not pass_sent:
                        if password:
                            os.write(master, (password + "\n").encode())
                            pass_sent = True
                        continue

                    if verbose:
                        sys.stdout.write(text)
                        sys.stdout.flush()

                except OSError:
                    break
            else:
                p_res, p_status = os.waitpid(pid, os.WNOHANG)
                if p_res != 0:
                    # Drain remaining output
                    try:
                        while True:
                            r2, _, _ = select.select([master], [], [], 0.1)
                            if not r2:
                                break
                            chunk = os.read(master, 4096)
                            if not chunk:
                                break
                            output += chunk
                            if verbose:
                                sys.stdout.write(chunk.decode("utf-8", errors="replace"))
                                sys.stdout.flush()
                    except OSError:
                        pass

                    os.close(master)
                    exit_code = os.waitstatus_to_exitcode(p_status) if hasattr(os, "waitstatus_to_exitcode") else (p_status >> 8)
                    return exit_code, output.decode("utf-8", errors="replace")

        os.close(master)
        try:
            _, status = os.waitpid(pid, 0)
            exit_code = os.waitstatus_to_exitcode(status) if hasattr(os, "waitstatus_to_exitcode") else (status >> 8)
        except ChildProcessError:
            exit_code = 0
        return exit_code, output.decode("utf-8", errors="replace")


def prompt_credentials():
    print("=" * 60)
    print("Chomp Wars - Batocera Deployment")
    print("=" * 60)
    host = input("Batocera hostname or IP: ").strip()
    while not host:
        print("Error: Hostname or IP is required.")
        host = input("Batocera hostname or IP: ").strip()

    user = input(f"SSH username for {host} [root]: ").strip()
    if not user:
        user = "root"

    password = getpass.getpass(f"SSH password for {user}@{host}: ")
    print()
    return host, user, password


def main():
    parser = argparse.ArgumentParser(description="Deploy Chomp Wars to a Batocera machine.")
    parser.add_argument("--host", help="Batocera hostname or IP address (prompted if omitted)")
    parser.add_argument("--user", help="SSH username (prompted if omitted)")
    parser.add_argument("--password", help="SSH password (prompted securely if omitted)")
    parser.add_argument("--port", type=int, default=22, help="SSH port (default: 22)")
    parser.add_argument("--skip-tests", action="store_true", help="Skip running the smoke test suite on Batocera")
    args = parser.parse_args()

    host = args.host or os.environ.get("BATOCERA_HOST")
    user = args.user or os.environ.get("BATOCERA_USER")
    password = args.password or os.environ.get("BATOCERA_PASSWORD")

    if not host or not user or password is None:
        h, u, p = prompt_credentials()
        host = host or h
        user = user or u
        password = password if password is not None else p

    # The game is the repository root. Batocera expects it in a folder named chomp-wars, so stage a
    # copy under that name, without git data, Godot's cache or local builds.
    script_path = Path(__file__).resolve()
    repo_root = script_path.parent.parent

    if not (repo_root / "project.godot").exists():
        print(f"Error: Could not find the Godot project at: {repo_root}")
        sys.exit(1)

    staging_root = Path(tempfile.mkdtemp(prefix="chomp-wars-deploy-"))
    atexit.register(shutil.rmtree, staging_root, True)
    chomp_wars_dir = staging_root / "chomp-wars"
    shutil.copytree(repo_root, chomp_wars_dir,
                    ignore=shutil.ignore_patterns(".git", ".godot", "build", "__pycache__"))

    print(f"[*] Connecting to {user}@{host}:{args.port}...")
    test_ssh_cmd = ["ssh", "-o", "StrictHostKeyChecking=no", "-p", str(args.port), f"{user}@{host}", "batocera-version"]
    code, out = run_ssh_or_scp(test_ssh_cmd, password=password, timeout=15, verbose=False)
    if code != 0:
        print(f"Error: Could not connect to {user}@{host}:{args.port}")
        print("Details:\n" + out)
        sys.exit(1)

    batocera_ver = out.strip().splitlines()[-1] if out.strip() else "Unknown"
    print(f"  ✓ Connected to Batocera ({batocera_ver})")

    # Sync game files to Batocera
    print("\n[*] Copying Chomp Wars game files to Batocera...")
    ensure_dir_cmd = ["ssh", "-o", "StrictHostKeyChecking=no", "-p", str(args.port), f"{user}@{host}", "mkdir -p /userdata/roms/steam/.data"]
    run_ssh_or_scp(ensure_dir_cmd, password=password, timeout=15, verbose=False)

    scp_cmd = ["scp", "-o", "StrictHostKeyChecking=no", "-P", str(args.port), "-r", str(chomp_wars_dir), f"{user}@{host}:/userdata/roms/steam/.data/"]
    code, scp_out = run_ssh_or_scp(scp_cmd, password=password, timeout=180, verbose=False)
    if code != 0:
        print(f"Error copying files to {host}:\n" + scp_out)
        sys.exit(1)
    print("  ✓ Game files transferred to /userdata/roms/steam/.data/chomp-wars")

    # Run deployment script on Batocera
    print("\n[*] Configuring and building Chomp Wars on Batocera...")
    setup_flag = "--skip-tests" if args.skip_tests else ""
    remote_cmd_str = f"bash /userdata/roms/steam/.data/chomp-wars/tools/remote_batocera_setup.sh {setup_flag}".strip()

    deploy_cmd = [
        "ssh",
        "-o", "StrictHostKeyChecking=no",
        "-p", str(args.port),
        f"{user}@{host}",
        remote_cmd_str
    ]
    code, deploy_out = run_ssh_or_scp(deploy_cmd, password=password, timeout=300, verbose=True)

    if code != 0 or "DEPLOYMENT_SUCCESS" not in deploy_out:
        print("\nDeployment encountered an error.")
        sys.exit(1)

    print("\n" + "=" * 60)
    print("✓ Deployment Successful!")
    print("Chomp Wars is ready to play under the Steam system on your Batocera machine.")
    print("=" * 60)


if __name__ == "__main__":
    main()

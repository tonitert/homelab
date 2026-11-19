# homelab

A NixOS flake for a spare laptop (`blackout`) that runs the
[gorilla-blackout](https://github.com/tonitert/gorilla-blackout) multiplayer
backend in a podman container. A Cloudflare Tunnel makes it public as
`https://api.blackout.beer`. The frontend stays on Cloudflare Pages
(`blackout.beer`). The laptop is installed over PXE, is reachable over
Tailscale, and keeps itself in sync with this repo on GitHub: push a change
and the laptop rebuilds itself within 5 minutes.

```
flake.nix                    hosts, installer, netboot files, apps, checks
hosts/blackout/              the laptop: identity, enabled features, hardware
modules/                     reusable homelab.* modules (all opt-in)
  base.nix                   admin user + SSH keys, NetworkManager, mDNS, Nix settings
  disk.nix                   disko layout: GPT, 1 GiB ESP, ext4 root (UEFI, systemd-boot)
  laptop-server.nix          ignore lid, never suspend, blank the screen
  containers.nix             podman, daily `podman auto-update`, containers retry every 30 s
  tunnel.nix                 Cloudflare Tunnel; services add hostname -> origin
  tailscale.nix              Tailscale client (log in once with `sudo tailscale up`)
  gitops.nix                 every 5 min: rebuild from the newest commit on GitHub
  services/gorilla-blackout.nix
.github/workflows/check.yml  builds the laptop's config on every push
installer/                   PXE installer (RAM-only, carries the whole system)
tests/pxe-install.nix        PXE boot -> install -> boot from disk, in QEMU
tools/                       pxe-server (pixiecore) and pxe-vm (local QEMU)
llm-jail.sh                  starts the Claude Code sandbox with enough RAM/disk for the test
```

## Overview

A full install, in order:

| Step | Where | Logins |
| --- | --- | --- |
| [0. Before you start](#0-before-you-start) | your machine | GitHub CLI, Tailscale on your machine |
| [1. Publish the backend image](#1-publish-the-backend-image) | gorilla-blackout repo | GitHub (already logged in) |
| [2. Cloudflare Tunnel](#2-cloudflare-tunnel) | your machine | Cloudflare |
| [3. Put the config on GitHub](#3-put-the-config-on-github) | your machine | GitHub (already logged in) |
| [4. Test the installer locally](#4-test-the-installer-locally) | your machine (optional) | none |
| [5. Install the laptop over PXE](#5-install-the-laptop-over-pxe) | the laptop | console password, SSH, tunnel credentials, Tailscale |
| [6. Check that everything works](#6-check-that-everything-works) | your machine | none |

Steps 0 to 3 are one-time setup. A reinstall only needs step 5 (see
[Reinstalling](#reinstalling)). A laptop that is already installed from an
older version of this repo needs
[a one-time deploy](#a-laptop-installed-before-tailscale-and-github-pulls)
instead of step 5.

The laptop itself never logs in to GitHub or ghcr.io: the repo and the image
are both public. These are all the credentials involved:

| Credential | Lives on | Created by | Needed again when |
| --- | --- | --- | --- |
| GitHub CLI login | your machine (`~/.config/gh`) | `gh auth login` (step 0) | pushing, `gh` commands |
| SSH keys | your devices; public keys in `hosts/blackout/default.nix` | you | adding a device: add its key and push |
| Console password for `toni` | the laptop | the installer asks (step 5) | logging in at the laptop's own keyboard |
| Cloudflare account certificate | your machine (`~/.cloudflared/cert.pem`) | `cloudflared tunnel login` (step 2) | creating tunnels or DNS routes |
| Tunnel credentials | your machine (`~/.cloudflared/<UUID>.json`), copied to the laptop (`/var/lib/secrets/cloudflared-tunnel.json`) | `cloudflared tunnel create` (step 2) | every (re)install. Keep a backup |
| Tailscale machine key | the laptop (`/var/lib/tailscale`) | `sudo tailscale up` (step 5) | lost on reinstall: log in again |

## 0. Before you start

You need:

- **Accounts:** GitHub (`tonitert`), Cloudflare (with the `blackout.beer`
  zone on it), and Tailscale.
- **Your machine:** x86_64 Linux with [Nix](https://nixos.org/download/) and
  flakes enabled (`experimental-features = nix-command flakes` in
  `nix.conf`). It must be on the same LAN as the laptop for the PXE install.
  KVM is needed only for the local test in step 4. Run all commands from a
  checkout of this repo.
- **Your SSH key** in `homelab.adminKeys` in `hosts/blackout/default.nix`.
  These are the keys from https://github.com/tonitert.keys. SSH into the
  laptop is key-only, so a device whose key isn't listed can't log in.
- **The laptop:** UEFI, more than 4 GB of RAM, and an Ethernet cable to the
  LAN (details in step 5).

Get the tools for the next steps:

```sh
nix shell nixpkgs#gh nixpkgs#cloudflared
```

**Log in to GitHub** (used for pushing in steps 1 and 3):

```sh
gh auth login
```

Answer the prompts: *GitHub.com* → *HTTPS* → *Authenticate Git with your
GitHub credentials?* **Yes** → *Login with a web browser*. Copy the one-time
code it shows, open https://github.com/login/device, paste the code and
authorize. `gh auth status` should then say you're logged in as `tonitert`.

**Log in to Tailscale on your machine** (and on your phone or other devices).
This is how you reach the laptop later from outside the LAN. Install it from
https://tailscale.com/download (on NixOS: `services.tailscale.enable =
true;`), then run `sudo tailscale up` and open the link it prints. Use the
account the laptop should join.

## 1. Publish the backend image

The laptop pulls `ghcr.io/tonitert/gorilla-blackout-backend:latest`. The
gorilla-blackout repo's *Publish backend image* workflow builds
`backend/Dockerfile` and pushes it there on every push to `master` that
touches `backend/`.

Start the first run by hand (GitHub → gorilla-blackout → Actions →
*Publish backend image* → Run workflow), or with
`gh workflow run publish-backend-image.yml`. Then make the package
**public**. A private package can't be pulled without logging in, and the
laptop doesn't log in. Go to GitHub → your profile → Packages →
gorilla-blackout-backend → Package settings → Danger Zone → Change
visibility → Public.

Check that anyone can pull it. This works without being logged in to ghcr.io
and prints the image's digest:

```sh
nix run nixpkgs#skopeo -- inspect docker://ghcr.io/tonitert/gorilla-blackout-backend:latest | grep -m1 '"Digest"'
```

## 2. Cloudflare Tunnel

The tunnel for this repo already exists. Its UUID is in
`hosts/blackout/default.nix` (`homelab.tunnel.id`). You only need this step
to log in to Cloudflare again, recover lost credentials, or make a new
tunnel.

**Log in to Cloudflare:**

```sh
cloudflared tunnel login
```

It prints a link (and tries to open it). Log in to Cloudflare, pick the
`blackout.beer` zone and click **Authorize**. This writes
`~/.cloudflared/cert.pem`, which lets `cloudflared` on your machine manage
tunnels and DNS in that zone. It stays on your machine; the laptop doesn't
need it.

**Create the tunnel** (only for a new one):

```sh
cloudflared tunnel create blackout        # prints the UUID, writes ~/.cloudflared/<UUID>.json
cloudflared tunnel route dns blackout api.blackout.beer
```

If `api.blackout.beer` already has a DNS record (for example, the current
backend), delete it first (Cloudflare dashboard → blackout.beer → DNS →
Records), or `route dns` will fail. Put the new UUID in
`hosts/blackout/default.nix` (`homelab.tunnel.id = "…";`).

`~/.cloudflared/<UUID>.json` is the tunnel's password: whoever has it can
serve `api.blackout.beer`. It stays out of the Nix store and out of Git. You
copy it to the laptop after every install (step 5), so keep a backup. If you
lose it, the login above lets you download it again:

```sh
cloudflared tunnel token --cred-file ~/.cloudflared/<UUID>.json blackout
```

Which hostnames go where (the tunnel's ingress rules) is set in Nix, by the
service modules.

## 3. Put the config on GitHub

The laptop pulls its config from `github:tonitert/homelab`
(`homelab.gitops.flake` in `hosts/blackout/default.nix`; change it if the
repo gets another name). The repo must be **public**: the laptop fetches it
without credentials. Nothing in it is secret: the SSH keys are public keys,
and the tunnel UUID is useless without the credentials JSON.

```sh
git add -A && git commit -m "Initial homelab config"
gh repo create tonitert/homelab --public --source . --push
```

The laptop builds whatever `main` points to, including its `flake.lock`, so
it only gets the nixpkgs version you pushed. Each push also runs the *Check*
workflow, which builds the laptop's config. Watch the first run with
`gh run watch`; it should finish green in a few minutes.

## 4. Test the installer locally

You need x86_64 Linux with KVM.

```sh
nix build .#checks.x86_64-linux.pxe-install -L
```

The automated test does the following:

1. OVMF UEFI firmware network-boots the installer, as the laptop would:
   DHCP/TFTP, then iPXE, then `netboot.ipxe`.
2. It checks that the installer refuses to run without confirmation.
3. It installs onto a blank virtio disk.
4. It boots that disk and checks:
   - the hostname, the ext4 root and vfat `/boot`;
   - sshd and your keys;
   - the container unit and the auto-update timer;
   - that the tunnel waits for its credentials instead of crash-looping;
   - that suspend is masked;
   - that Tailscale runs and waits for a login;
   - that the pull check fails cleanly while the repo is unreachable, and
     starts `nixos-rebuild` once there is a commit the machine isn't
     running.

The test is the real `blackout` config with two differences. It follows a
Git repo the test creates inside the VM instead of GitHub, so the VM never
rebuilds itself into the real config. And it leaves out linux-firmware:
QEMU doesn't need it, and it's 825 MB that squashfs can't compress further.
Without it the installer initrd is about 0.7 GB instead of 1.5 GB. The
sandbox has no network, so the test can't pull the image from ghcr.

The test VMs get 4 GB of RAM each. On a smaller machine, or to iterate
faster, run the test driver directly instead. `PXE_TEST_MEM` sets the RAM per
VM in MiB. The VM disk goes to `$TMPDIR` and grows to about 2.5 GB:

```sh
PXE_TEST_MEM=2048 nix run .#checks.x86_64-linux.pxe-install.driver
```

Run this way, the VMs have internet access. The installed system then really
tries to pull `ghcr.io/tonitert/gorilla-blackout-backend:latest`. Until
step 1 is done, that pull fails with `403 Forbidden`.

To click through the real interactive installer in your terminal:

```sh
nix run .#pxe-vm               # UEFI PXE boot; press Enter, pick /dev/vda, type YES
nix run .#pxe-vm -- --disk     # boot the installed system (ssh -p 2222 toni@localhost)
nix run .#pxe-vm -- --reset    # start over
```

Quit QEMU with `Ctrl-A X`. The VM files live in `./.pxe-vm`.

Finish the install before you use `--disk`. On an empty disk the firmware
falls back to its own network boot, which fails with `PXE-E16: No valid offer
received`. `pxe-vm` now refuses to boot an empty disk.

The VM gets 4 GB of RAM, the laptop's minimum. If the PXE boot stops with
`EFI stub: ERROR: Failed to load initrd: 0x8000000000000009` (out of memory,
see step 5), give it more: `PXE_VM_MEM=6144 nix run .#pxe-vm`.

## 5. Install the laptop over PXE

Run this from a checkout of what you pushed in step 3, with no uncommitted
changes (`git status` lists nothing modified). The installed system then
records that commit, and its first check against GitHub finds nothing to do.
An installer built from other changes works too: the laptop replaces them
with GitHub's version on its first check, 5 minutes after it boots.

1. **Laptop firmware settings:** UEFI mode, **Secure Boot off** (iPXE and
   NixOS aren't signed), and network/PXE boot enabled. Connect it to the
   LAN by Ethernet. It needs more than 4 GB of RAM to boot reliably. The
   installer runs from RAM and carries the whole system offline: the initrd
   is about 1.5 GB, more than half of it linux-firmware. Memory peaks twice
   at about 3 GB. First, before the kernel starts, iPXE and the kernel's EFI
   stub each hold a copy. Second, while the kernel unpacks it. In a 4 GB VM,
   the EFI stub ran out of memory for its copy in 2 of 4 boots; 6 GB worked.
2. On your machine, start the PXE server:
   ```sh
   nix run .#pxe-server
   ```
   It uses sudo and runs pixiecore in proxyDHCP mode, so the router stays
   the DHCP server. Open UDP 67, 69 and 4011 and TCP 64172 on that machine
   while it runs.
3. Network-boot the laptop (usually F12 at power-on).
4. The installer comes up on screen. Press Enter, check the disk it picked,
   and type `YES`. It partitions the disk and copies the system (no internet
   needed). Then it asks you to choose a **console password** for `toni`,
   twice. That password is only for logging in at the laptop's own keyboard;
   SSH uses keys only, and `sudo` asks for no password. Then it reboots into
   the installed system. You can also SSH in as root
   (`ssh root@blackout-installer.local`) and run
   `install-blackout [--disk /dev/sda]`.
5. Stop the PXE server (Ctrl-C). Any machine that network-boots while it runs
   gets the installer, although the installer never wipes a disk until
   someone types YES.
6. **SSH in** once to check access and accept the laptop's host key:
   ```sh
   ssh toni@blackout.local
   ```
   `blackout.local` is resolved over mDNS. If your machine can't resolve it
   (on Linux this needs nss-mdns; on NixOS, `services.avahi.nssmdns4 =
   true;`), use the laptop's IP instead. Your router's DHCP client list
   shows it, or log in at the laptop with the console password and run
   `ip -4 addr`.
7. **Copy the tunnel credentials** over. `<UUID>` is `homelab.tunnel.id`
   from `hosts/blackout/default.nix`. The tunnel starts by itself once the
   file exists:
   ```sh
   scp ~/.cloudflared/<UUID>.json toni@blackout.local:
   ssh toni@blackout.local 'sudo install -D -m 600 <UUID>.json /var/lib/secrets/cloudflared-tunnel.json && rm <UUID>.json'
   ```
8. **Log in to Tailscale** on the laptop:
   ```sh
   ssh -t toni@blackout.local sudo tailscale up
   ```
   It prints `To authenticate, visit:` and a link. Open the link on any
   device, sign in with the same Tailscale account as your other devices,
   and confirm adding `blackout`. The command then prints `Success.` and
   exits. The login is stored on the laptop and survives reboots and
   rebuilds. Then, in the admin console (https://login.tailscale.com/admin/machines):
   - If the tailnet has **device approval** turned on, `blackout` shows
     *Needs approval*: click ⋯ → Approve.
   - Click ⋯ next to `blackout` → **Disable key expiry**. Otherwise the
     laptop drops off the tailnet after 180 days until someone logs in
     again.

   From your devices, `ssh toni@blackout` now works from anywhere. The short
   name needs MagicDNS, which new tailnets have on by default (admin console
   → DNS). Without MagicDNS, use the laptop's Tailscale IP: `tailscale ip -4`
   on the laptop.
9. Do the checks in step 6.

## 6. Check that everything works

Run these from your machine. On the LAN, `blackout.local` works; from
anywhere else, use `blackout` over Tailscale.

- **SSH, both ways:** `ssh toni@blackout.local true` and `ssh toni@blackout true`
  both return without a password prompt.
- **Backend container:** `ssh toni@blackout systemctl is-active podman-gorilla-blackout-backend`
  prints `active`. Its first start pulls the image, so give it a minute.
- **Tunnel:** `cloudflared tunnel info blackout` lists at least one
  connector. If it lists none, see `journalctl -u 'cloudflared-tunnel-*'`
  on the laptop and check that step 5.7 put the file in the right place.
- **Public API:** `curl -i https://api.blackout.beer/api/lobbies/NOPE`
  returns a JSON 404 from the backend. Then play at https://blackout.beer.
  The frontend's backend URL (`VITE_PUBLIC_BACKEND_URL` in Cloudflare
  Pages) must be `https://api.blackout.beer`, which is its default.
- **Tailscale:** `tailscale status` on your machine lists `blackout`, and
  `ssh toni@blackout tailscale status` shows the laptop logged in.
- **Pulls from GitHub:**
  ```sh
  ssh toni@blackout nixos-version --configuration-revision   # same as `git rev-parse HEAD`
  ssh toni@blackout systemctl list-timers nixos-upgrade      # next check within 5 minutes
  ssh toni@blackout journalctl -u nixos-upgrade -n 5         # "already running the newest commit ..."
  ```
  To see a full round trip, push any small commit (a comment change is
  enough) and watch `ssh toni@blackout journalctl -fu nixos-upgrade`.
  Within 5 minutes it prints `updating to github:tonitert/homelab at <commit>`,
  rebuilds, and `nixos-version --configuration-revision` shows the new commit.

## A laptop installed before Tailscale and GitHub pulls

A laptop installed from an older version of this repo has neither Tailscale
nor the GitHub pulls. Do steps 0 to 3 first, then deploy once from your
machine, from a checkout of the commit you pushed with no uncommitted
changes:

```sh
nixos-rebuild switch --flake .#blackout --target-host toni@blackout.local --sudo
```

Older versions of nixos-rebuild call `--sudo` `--use-remote-sudo`. Without
NixOS on your machine, run it as `nix run nixpkgs#nixos-rebuild -- switch …`
with the same arguments.

Then finish as after a fresh install:

1. Copy the tunnel credentials (step 5.7), if you haven't already.
2. Log in to Tailscale (step 5.8).
3. Do the checks in step 6.

From then on, the laptop follows GitHub by itself.

## Reinstalling

Step 5 again. The GitHub pulls start by themselves, but some state lived only
on the old install:

- **SSH host keys** are new, so SSH warns that the host key changed. Remove
  the old ones: `ssh-keygen -R blackout.local; ssh-keygen -R blackout`.
- **Tunnel credentials:** copy the same `<UUID>.json` again (step 5.7).
- **Tailscale:** first delete the old `blackout` in the admin console
  (Machines → ⋯ → Remove). Otherwise the new install is named `blackout-1`.
  Then log in again (step 5.8).
- **Wi-Fi networks** set up with `nmtui` aren't in Git. Set them up again.

## Day-to-day

- **Change the config / upgrade NixOS:** edit (optionally run
  `nix flake update`), commit and push to `main`, or edit the file on
  github.com. Every 5 minutes the laptop compares the newest commit with the
  one it runs (`nixos-version --configuration-revision`) and, if they
  differ, runs `nixos-rebuild switch` from GitHub. The *Check* workflow
  shows on the commit whether the config builds. A commit that doesn't
  build changes nothing; the laptop retries every 5 minutes until a fixed
  commit arrives.
  - Apply right away: `ssh toni@blackout sudo systemctl start nixos-upgrade`
  - Watch it: `ssh toni@blackout journalctl -fu nixos-upgrade`
  - Try a change without pushing: the next check would replace it with
    GitHub's version, so pause the checks first, then deploy:
    ```sh
    ssh toni@blackout.local sudo systemctl stop nixos-upgrade.timer
    nixos-rebuild switch --flake .#blackout --target-host toni@blackout.local --sudo
    ```
    The timer starts again at the next boot, or with
    `sudo systemctl start nixos-upgrade.timer`.
  - A pushed config that breaks the laptop's network can't be fixed by
    pushing again. Reboot it and pick an older generation in the boot menu;
    it then pulls your fix.
- **Tailscale settings** (e.g. Tailscale SSH, exit node): add flags to
  `services.tailscale.extraSetFlags` in `hosts/blackout/default.nix`, e.g.
  `[ "--ssh" ]`, and push. They are applied with `tailscale set`.
- **New backend version:** push to gorilla-blackout `master`. The workflow
  publishes `:latest`, and the laptop's daily `podman auto-update` pulls it
  and restarts the container. To update right away:
  `ssh toni@blackout sudo podman auto-update`.
- **Logs:**
  - `journalctl -u podman-gorilla-blackout-backend`
  - `journalctl -u 'cloudflared-tunnel-*'`
  - `journalctl -u nixos-upgrade` (pulls from GitHub)
  - `journalctl -u tailscaled`, `tailscale status`

## Adding things later

- **Another service:** copy `modules/services/gorilla-blackout.nix`. A
  service is an oci-container bound to `127.0.0.1` plus a
  `homelab.tunnel.ingress."<host>" = "http://127.0.0.1:<port>"` entry.
  Import the new file in `modules/default.nix`, enable it in
  `hosts/blackout/default.nix`, and run `cloudflared tunnel route dns
  blackout <host>`. For a one-off, you can also define
  `virtualisation.oci-containers.containers.<name>` straight in the host
  file.
- **Another machine:** create `hosts/<name>/default.nix` and add
  `<name> = mkHost "<name>" [ ];` (plus
  `<name>-installer = mkInstaller self.nixosConfigurations.<name> [ ];` if it
  should be PXE-installable) in `flake.nix`. Set
  `homelab.gitops.flake = "github:tonitert/homelab";` in its host file if
  it should follow GitHub too.
- **A disk the installer doesn't know:** add it to
  `homelab.installer.candidateDisks`. It currently knows nvme0n1, sda,
  mmcblk0 and vda.
- **A new SSH key:** add it to `homelab.adminKeys` and push. The laptop
  picks it up at its next check.

# Linux & Ubuntu — The Complete Bible
**Platform**: Linux Kernel · Ubuntu LTS (20.04 / 22.04 / 24.04)  
**Category**: Operating Systems · DevOps · Infrastructure · SRE · Principal Engineer Reference

> "Linux is not an operating system unto itself, but rather another free component of a fully functioning GNU system." — Richard Stallman
> "Talk is cheap. Show me the code." — Linus Torvalds

---

## Why This Matters for FAANG PE Interviews

Every FAANG production system runs on Linux. As a principal engineer, you are expected to:
- Diagnose live production incidents via SSH with no GUI
- Reason about kernel behaviour (scheduler, OOM killer, file descriptors)
- Design systems that exploit Linux primitives (epoll, cgroups, namespaces)
- Mentor engineers on Linux internals without handwaving

This document is a complete reference — history, architecture, commands, service management, and production patterns.

---

## Table of Contents

1. [History & Philosophy](#1-history--philosophy)
2. [OS Architecture — The Big Picture](#2-os-architecture--the-big-picture)
3. [Kernel Internals](#3-kernel-internals)
4. [Filesystem Hierarchy Standard (FHS)](#4-filesystem-hierarchy-standard-fhs)
5. [Boot Process — From Power-On to Login](#5-boot-process--from-power-on-to-login)
6. [Users, Groups & Permissions](#6-users-groups--permissions)
7. [Process Management](#7-process-management)
8. [File & Directory Operations](#8-file--directory-operations)
9. [Text Processing & Pipelines](#9-text-processing--pipelines)
10. [Networking](#10-networking)
11. [Package Management (APT, dpkg, Snap, Flatpak)](#11-package-management)
12. [Disk, Filesystem & Storage](#12-disk-filesystem--storage)
13. [Systemd & Service Management](#13-systemd--service-management)
14. [Setting Up Common Services](#14-setting-up-common-services)
15. [Cron & Scheduled Tasks](#15-cron--scheduled-tasks)
16. [Shell & Scripting](#16-shell--scripting)
17. [Environment Variables & Configuration](#17-environment-variables--configuration)
18. [Monitoring & Observability](#18-monitoring--observability)
19. [Security & Hardening](#19-security--hardening)
20. [Performance Tuning](#20-performance-tuning)
21. [Containers & Linux Primitives](#21-containers--linux-primitives)
22. [Quick Reference Cards](#22-quick-reference-cards)

---

## 1. History & Philosophy

### Timeline

| Year | Event |
|------|-------|
| 1969 | Unix created at Bell Labs (Thompson, Ritchie) — C + small composable tools |
| 1983 | GNU Project launched by Stallman — free software movement begins |
| 1991 | Linus Torvalds posts Linux kernel 0.01 (Minix-inspired, x86 only) |
| 1992 | Linux licensed under GPL v2 — free software + copyleft |
| 1993 | Debian and Slackware — first proper distributions |
| 1994 | Linux 1.0 released — 176,000 lines of code |
| 1996 | Tux the penguin becomes Linux mascot |
| 2000 | IBM announces $1B investment in Linux |
| 2004 | Ubuntu 4.10 "Warty Warthog" released by Canonical |
| 2008 | Android (Linux kernel) ships on first commercial device |
| 2011 | Linux 3.0, kernel reaches ~15M lines of code |
| 2016 | Microsoft adds Linux Subsystem to Windows (WSL) |
| 2020 | Linux runs on 100% of Top 500 supercomputers |
| 2023 | Linux kernel 6.x — ARM64, RISC-V, eBPF, io_uring mature |

### The Unix Philosophy (Still Governs Linux Design)

1. **Write programs that do one thing and do it well**
2. **Write programs to work together**
3. **Write programs to handle text streams** — universal interface

### GNU/Linux vs Linux

- **Linux** = the kernel only (memory management, scheduling, drivers)
- **GNU** = the userland tools (bash, gcc, glibc, coreutils)
- **Distribution** = kernel + GNU tools + package manager + init system + desktop (optional)
- **Ubuntu** = Debian-based distro by Canonical, LTS releases every 2 years, supported 5 years

### Ubuntu LTS Release Cadence

| Release | Codename | LTS Until |
|---------|----------|-----------|
| 20.04 | Focal Fossa | April 2025 (ESM 2030) |
| 22.04 | Jammy Jellyfish | April 2027 (ESM 2032) |
| 24.04 | Noble Numbat | April 2029 (ESM 2034) |

---

## 2. OS Architecture — The Big Picture

```
┌───────────────────────────────────────────────────────────────┐
│                        USER SPACE                             │
│                                                               │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────────┐│
│  │ Applications│  │System Daemons│  │  Shell (bash/zsh)    ││
│  │ (nginx, db) │  │ (sshd, cron) │  │  CLI tools (ls, grep)││
│  └──────┬──────┘  └──────┬───────┘  └──────────┬───────────┘│
│         │                │                       │            │
│  ┌──────▼────────────────▼───────────────────────▼──────────┐│
│  │              C Standard Library (glibc)                   ││
│  │   malloc, printf, fopen, socket, pthread ...              ││
│  └──────────────────────────┬────────────────────────────────┘│
└─────────────────────────────│─────────────────────────────────┘
                              │  System Calls (syscall interface)
┌─────────────────────────────▼─────────────────────────────────┐
│                        KERNEL SPACE                            │
│                                                               │
│  ┌────────────┐  ┌────────────┐  ┌──────────┐  ┌──────────┐ │
│  │  Process   │  │  Memory    │  │  VFS     │  │ Network  │ │
│  │ Scheduler  │  │  Manager   │  │ (ext4,   │  │  Stack   │ │
│  │ (CFS)      │  │  (buddy,   │  │  xfs,    │  │  (TCP/IP)│ │
│  │            │  │   slab)    │  │  tmpfs)  │  │          │ │
│  └────────────┘  └────────────┘  └──────────┘  └──────────┘ │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │           Device Drivers & Hardware Abstraction         │  │
│  └────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼─────────────────────────────────┐
│                        HARDWARE                                │
│        CPU   RAM   Disk   NIC   GPU   USB   ...               │
└───────────────────────────────────────────────────────────────┘
```

### Key Boundaries

| Boundary | Mechanism | Why It Matters |
|----------|-----------|----------------|
| User ↔ Kernel | System calls | Security isolation; kernel bugs crash the whole system |
| Process ↔ Process | Virtual memory, namespaces | Each process sees its own address space |
| Kernel ↔ Hardware | Device drivers, IRQs | Bad drivers can cause kernel panics |

### System Call Numbers (Common)

```
read(0)      write(1)     open(2)      close(3)
stat(4)      fstat(5)     mmap(9)      mprotect(10)
munmap(11)   brk(12)      ioctl(16)    readv(19)
socket(41)   connect(42)  accept(43)   sendto(44)
recvfrom(45) bind(49)     listen(50)   fork(57)
execve(59)   exit(60)     wait4(61)    kill(62)
clone(56)    futex(202)   epoll_create1(291)
```

Trace syscalls live: `strace -p <pid>` or `strace <command>`

---

## 3. Kernel Internals

### Process Scheduler — Completely Fair Scheduler (CFS)

- Default scheduler since Linux 2.6.23
- Uses a **red-black tree** ordered by virtual runtime (`vruntime`)
- Process with smallest `vruntime` runs next
- **Time slice**: not fixed — proportional to `nice` value weight
- **Preemption**: process is preempted when a higher-priority process becomes runnable

```
Nice range: -20 (highest priority) to +19 (lowest priority)
Default nice: 0

Real-time scheduling classes (above CFS):
  SCHED_FIFO   — run until done or preempted by higher RT
  SCHED_RR     — round-robin among same priority RT tasks
  SCHED_NORMAL — CFS (default)
  SCHED_BATCH  — lower priority, CPU-bound background
  SCHED_IDLE   — lowest, only when nothing else runnable
```

### Memory Management

```
Virtual Address Space Layout (64-bit):
  0x0000000000000000 - 0x00007fffffffffff  → User space (128 TB)
  0xffff800000000000 - 0xffffffffffffffff  → Kernel space (128 TB)

Per-process layout (bottom to top):
  [text segment]    — executable code (read-only)
  [data segment]    — global/static variables
  [BSS]             — uninitialized global variables
  [heap]            — malloc/free (grows upward via brk/mmap)
  ...
  [stack]           — function frames (grows downward)
  [vdso/vsyscall]   — kernel-mapped fast syscall helpers
```

**Page fault handling:**
1. Process accesses unmapped address → CPU raises page fault
2. Kernel checks `vm_area_struct` — is it a valid mapping?
3. If valid: allocate page frame, update page table, resume
4. If invalid: send `SIGSEGV` → segmentation fault

**OOM Killer:**
- When system runs out of memory, kernel OOM killer selects a process to kill
- Selection based on `oom_score` (higher = more likely to be killed)
- Check: `cat /proc/<pid>/oom_score`
- Protect a process: `echo -1000 > /proc/<pid>/oom_score_adj`
- View OOM kills: `dmesg | grep -i "oom\|killed"`

### File Descriptor Table

Every process has:
- **File Descriptor Table** — per-process array of open file descriptions
- **File Description** (kernel) — offset, flags, inode pointer
- **Inode** — actual file metadata (permissions, size, blocks)

```
FD 0 → stdin   (terminal or pipe read end)
FD 1 → stdout  (terminal or pipe write end)
FD 2 → stderr
FD 3+ → opened by the process
```

Default limit: `ulimit -n` (typically 1024; production: 65535+)
System-wide: `cat /proc/sys/fs/file-max`

### Signals

| Signal | Number | Default Action | Meaning |
|--------|--------|----------------|---------|
| SIGHUP | 1 | Terminate | Hangup (reload config when caught) |
| SIGINT | 2 | Terminate | Ctrl+C |
| SIGQUIT | 3 | Core dump | Ctrl+\ |
| SIGKILL | 9 | Terminate | Cannot be caught or ignored |
| SIGSEGV | 11 | Core dump | Invalid memory access |
| SIGTERM | 15 | Terminate | Graceful shutdown request |
| SIGSTOP | 19 | Stop | Cannot be caught or ignored |
| SIGCONT | 18 | Continue | Resume stopped process |
| SIGUSR1/2 | 10/12 | Terminate | User-defined |
| SIGCHLD | 17 | Ignore | Child process changed state |

---

## 4. Filesystem Hierarchy Standard (FHS)

```
/
├── bin/         → Essential user binaries (ls, cp, bash) — symlink to /usr/bin on modern Ubuntu
├── sbin/        → System binaries (fdisk, ifconfig) — symlink to /usr/sbin
├── usr/
│   ├── bin/     → Non-essential user binaries
│   ├── sbin/    → Non-essential system binaries
│   ├── lib/     → Shared libraries
│   ├── local/   → Locally compiled software (not managed by apt)
│   └── share/   → Architecture-independent data (docs, icons)
├── etc/         → System configuration files (text, human-editable)
│   ├── passwd   → User accounts (no passwords — those are in shadow)
│   ├── shadow   → Hashed passwords (root-only readable)
│   ├── group    → Group definitions
│   ├── hosts    → Static hostname-to-IP mappings
│   ├── fstab    → Filesystem mount table
│   ├── crontab  → System cron jobs
│   ├── sudoers  → Sudo permissions (edit with visudo)
│   └── systemd/ → Systemd unit files
├── var/
│   ├── log/     → Log files (syslog, auth.log, kern.log)
│   ├── spool/   → Queued data (mail, print)
│   ├── cache/   → Cached application data
│   └── run/     → Runtime PID files, sockets (symlink to /run)
├── tmp/         → Temporary files (cleared on reboot)
├── home/        → User home directories (/home/username)
├── root/        → Root user's home directory
├── dev/
│   ├── sda      → First SATA/SCSI disk
│   ├── sda1     → First partition of sda
│   ├── nvme0n1  → First NVMe disk
│   ├── null     → Bit bucket (discard everything written)
│   ├── zero     → Source of null bytes
│   ├── urandom  → Non-blocking random number source
│   ├── random   → Blocking random number source (entropy pool)
│   └── tty      → Current terminal
├── proc/        → Virtual filesystem — kernel data structures as files
│   ├── cpuinfo  → CPU information
│   ├── meminfo  → Memory statistics
│   ├── loadavg  → System load average
│   ├── <pid>/   → Per-process directory
│   └── sys/     → Kernel tunables (sysctl)
├── sys/         → Virtual filesystem — device/driver/kernel info
├── run/         → Runtime data (PIDs, sockets, since last boot)
├── lib/         → Essential shared libraries and kernel modules
├── boot/        → Kernel image, initrd, GRUB bootloader
├── mnt/         → Temporary mount point
├── media/       → Removable media mount points (USB, CD)
└── opt/         → Optional/third-party software packages
```

### Important /proc Files

```bash
cat /proc/cpuinfo           # CPU model, cores, flags
cat /proc/meminfo           # Memory usage in detail
cat /proc/loadavg           # 1, 5, 15 minute load averages
cat /proc/uptime            # Seconds since boot
cat /proc/version           # Kernel version string
cat /proc/mounts            # Currently mounted filesystems
cat /proc/net/dev           # Network interface statistics
cat /proc/<pid>/status      # Process status (state, memory, threads)
cat /proc/<pid>/maps        # Memory map of a process
cat /proc/<pid>/fd/         # Open file descriptors
cat /proc/<pid>/cmdline     # Command that started the process
cat /proc/<pid>/environ     # Environment variables
ls -la /proc/<pid>/fd       # Count open FDs: ls /proc/<pid>/fd | wc -l
```

---

## 5. Boot Process — From Power-On to Login

```
POWER ON
   │
   ▼
BIOS/UEFI Firmware
   │  POST (Power-On Self Test)
   │  Locate bootable device
   │
   ▼
GRUB2 Bootloader  (/boot/grub/grub.cfg)
   │  Loads kernel image (/boot/vmlinuz-x.x.x)
   │  Loads initrd (/boot/initrd.img-x.x.x)
   │
   ▼
Kernel Initialization
   │  Decompress kernel
   │  Initialize memory, scheduler, interrupt handlers
   │  Mount initramfs (temporary root filesystem in RAM)
   │  Find and mount real root filesystem
   │
   ▼
systemd (PID 1)  — /sbin/init → /lib/systemd/systemd
   │  Reads /etc/systemd/system/ and /lib/systemd/system/
   │  Processes unit files in dependency order
   │  Reaches default.target (usually graphical.target or multi-user.target)
   │
   ▼
Login Manager (getty / GDM / LightDM)
   │
   ▼
User Shell / Desktop Session
```

### GRUB2 Key Files

```bash
/boot/grub/grub.cfg          # Generated config — do not edit directly
/etc/default/grub            # Edit this for GRUB settings
/etc/grub.d/                 # Scripts that generate grub.cfg

# After editing /etc/default/grub:
sudo update-grub             # Regenerates grub.cfg

# GRUB_TIMEOUT=5             # Seconds to show menu
# GRUB_DEFAULT=0             # Default boot entry
# GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"  # Kernel boot params
```

### Kernel Boot Parameters (via GRUB)

```
quiet         — suppress most boot messages
splash        — show splash screen
ro            — mount root read-only initially
nomodeset     — disable kernel mode-setting (GPU fallback)
single        — boot into single-user/recovery mode
init=/bin/bash — bypass init, drop to root shell (recovery)
systemd.unit=rescue.target — rescue mode via systemd
mem=4G        — limit RAM (testing)
```

### systemd Targets (Runlevels)

| SysV Runlevel | systemd Target | Description |
|---------------|----------------|-------------|
| 0 | poweroff.target | Halt |
| 1 | rescue.target | Single-user/rescue |
| 2,3,4 | multi-user.target | Multi-user, no GUI |
| 5 | graphical.target | Multi-user + GUI |
| 6 | reboot.target | Reboot |

```bash
systemctl get-default                    # Show current default target
systemctl set-default multi-user.target  # Change default target
systemctl isolate rescue.target          # Switch target now (no reboot)
```

---

## 6. Users, Groups & Permissions

### User Management

```bash
# Create user
sudo useradd -m -s /bin/bash -c "Full Name" username
sudo useradd -m -s /bin/bash -G sudo,docker username  # with groups

# Better: adduser (interactive, Debian/Ubuntu)
sudo adduser username

# Set password
sudo passwd username

# Modify user
sudo usermod -aG sudo username        # Add to sudo group (-a = append)
sudo usermod -s /bin/zsh username     # Change shell
sudo usermod -d /new/home username    # Change home dir
sudo usermod -l newname oldname       # Rename user
sudo usermod -L username              # Lock account
sudo usermod -U username              # Unlock account

# Delete user
sudo userdel username                 # Remove user (keep home)
sudo userdel -r username              # Remove user and home directory

# Switch user
su - username                         # Login as user (full environment)
su username                           # Switch without login environment
sudo -u username command              # Run single command as user
sudo -i                               # Root shell with root environment
sudo -s                               # Root shell with current environment

# Who is logged in
who                                   # Current sessions
w                                     # Sessions + what they're doing
last                                  # Login history
lastb                                 # Failed login attempts
id username                           # Show UID, GID, groups
groups username                       # List groups for user
```

### /etc/passwd Format

```
username:x:UID:GID:comment:home_dir:shell
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
rahul:x:1000:1000:Rahul Bisht:/home/rahul:/bin/bash
```

### /etc/shadow Format

```
username:hashed_password:last_change:min_age:max_age:warn:inactive:expire
rahul:$6$salt$hash...:19000:0:99999:7:::
```

### File Permissions

```
-rwxrw-r-- 1 owner group size date filename

File type: - (file), d (dir), l (symlink), b (block dev), c (char dev), p (pipe), s (socket)
Owner: rwx = 7
Group: rw- = 6
Other: r-- = 4

Permission bits:
  r = 4 (read)
  w = 2 (write)
  x = 1 (execute)

Special bits:
  SUID (4000): Execute as file owner (e.g., /usr/bin/passwd)
  SGID (2000): Execute as group; new files inherit group (dirs)
  Sticky (1000): Only owner can delete their files (e.g., /tmp)
```

```bash
# Change permissions
chmod 755 file              # rwxr-xr-x
chmod u+x file              # Add execute for owner
chmod go-w file             # Remove write for group and other
chmod -R 644 /path/         # Recursive
chmod 4755 /usr/bin/binary  # SUID
chmod 1777 /tmp             # Sticky bit

# Change ownership
chown user:group file
chown -R user:group /path/
chown :group file           # Change group only
chgrp group file            # Change group only

# Default permissions
umask                       # Show current umask (default 022)
umask 027                   # New files: 640, dirs: 750

# Access Control Lists (ACL)
setfacl -m u:username:rw file     # Give specific user rw
setfacl -m g:groupname:r file     # Give specific group read
getfacl file                       # View ACLs
setfacl -b file                    # Remove all ACLs

# Check effective permissions
sudo -u username stat file
namei -l /path/to/file      # Show permissions along path
```

### Sudo Configuration

```bash
# Edit safely
sudo visudo

# /etc/sudoers format:
# user  hosts=(run_as_user:run_as_group)  commands
root    ALL=(ALL:ALL) ALL
%sudo   ALL=(ALL:ALL) ALL                    # Group sudo: all commands
deploy  ALL=(ALL) NOPASSWD: /bin/systemctl   # No password for specific cmd
rahul   ALL=(ALL) /usr/bin/apt, /bin/systemctl  # Multiple commands

# Include drop-in files
#includedir /etc/sudoers.d/
```

---

## 7. Process Management

### Viewing Processes

```bash
# Process snapshots
ps aux                        # All processes, user-oriented format
ps -ef                        # All processes, full format
ps -eo pid,ppid,cmd,%cpu,%mem --sort=-%cpu  # Custom columns, sorted
ps -p 1234 -o pid,comm,etime  # Specific PID

# Tree view
pstree                        # ASCII tree of all processes
pstree -p                     # Include PIDs
pstree -p username            # Tree for specific user

# Dynamic view
top                           # Real-time process monitor
htop                          # Enhanced top (sudo apt install htop)
atop                          # Historical resource usage

# top key bindings:
#   k — kill process
#   r — renice
#   M — sort by memory
#   P — sort by CPU
#   1 — per-CPU display
#   q — quit

# Find processes
pgrep nginx                   # PIDs matching pattern
pgrep -u root ssh             # PIDs for user root matching ssh
pidof nginx                   # All PIDs for exact name
```

### Process Control

```bash
# Run in background
command &                     # Start in background
nohup command &               # Immune to SIGHUP (survives logout)
disown %1                     # Disown from shell's job table

# Job control
jobs                          # List background jobs
fg %1                         # Bring job 1 to foreground
bg %1                         # Resume job 1 in background
Ctrl+Z                        # Suspend foreground process
Ctrl+C                        # Send SIGINT to foreground process

# Kill processes
kill <pid>                    # Send SIGTERM (15) — graceful
kill -9 <pid>                 # Send SIGKILL — immediate (no cleanup)
kill -HUP <pid>               # Send SIGHUP — reload config
killall nginx                 # Kill all processes named nginx
pkill -f "python script.py"   # Kill by pattern match on full command
pkill -u username             # Kill all processes owned by user

# Priority
nice -n 10 command            # Start with lower priority (10)
nice -n -5 command            # Start with higher priority (needs sudo)
renice 10 -p <pid>            # Change priority of running process
renice 10 -u username         # Change priority of all user's processes

# Process limits
ulimit -a                     # Show all limits
ulimit -n 65535               # Set open file limit (current session)
ulimit -u 4096                # Max user processes

# Persistent limits: /etc/security/limits.conf
# nginx soft nofile 65535
# nginx hard nofile 65535
```

### Process States

| State | Code | Meaning |
|-------|------|---------|
| Running | R | On CPU or runnable |
| Sleeping | S | Interruptible wait (waiting for I/O, signal) |
| Disk Sleep | D | Uninterruptible wait (I/O in progress) — cannot be killed |
| Zombie | Z | Exited but parent hasn't reaped it |
| Stopped | T | Suspended (Ctrl+Z or SIGSTOP) |
| Tracing | t | Stopped by debugger |

```bash
# Find D-state (uninterruptible) processes — often I/O hung
ps aux | awk '$8 == "D"'

# Find zombie processes
ps aux | awk '$8 == "Z"'
```

### /proc Per-Process Files

```bash
ls /proc/<pid>/
cat /proc/<pid>/status         # State, memory, threads
cat /proc/<pid>/cmdline        # null-separated args
cat /proc/<pid>/environ        # null-separated environment
ls -la /proc/<pid>/fd          # Open file descriptors
cat /proc/<pid>/net/tcp        # Network connections
cat /proc/<pid>/maps           # Memory-mapped regions
cat /proc/<pid>/smaps          # Detailed memory breakdown
cat /proc/<pid>/io             # I/O statistics
```

---

## 8. File & Directory Operations

### Navigation

```bash
pwd                           # Print working directory
cd /path/to/dir               # Absolute path
cd ../..                      # Go up two levels
cd -                          # Previous directory
cd ~                          # Home directory
cd ~username                  # Another user's home

# Directory stack
pushd /path                   # Push to stack and cd
popd                          # Pop from stack and return
dirs                          # Show directory stack
```

### Listing

```bash
ls -la                        # Long format, all files
ls -lah                       # Human-readable sizes
ls -lt                        # Sort by modification time (newest first)
ls -ltr                       # Sort by time, oldest first
ls -lS                        # Sort by size, largest first
ls -d */                      # Directories only
ls -la /path/*.conf           # Glob pattern
ls --color=always | less -R   # Colored output piped to less
```

### File Operations

```bash
# Copy
cp source dest
cp -r source_dir dest_dir     # Recursive
cp -a source dest             # Archive (preserve permissions, timestamps)
cp -p source dest             # Preserve permissions
cp -n source dest             # No-clobber (don't overwrite)
cp -u source dest             # Update (copy only if source is newer)
cp -v source dest             # Verbose

# Move/Rename
mv source dest
mv -n source dest             # No-clobber
mv -b source dest             # Backup existing dest
mv -v source dest             # Verbose

# Delete
rm file
rm -f file                    # Force (no error if not exist)
rm -r dir/                    # Recursive
rm -rf dir/                   # Force recursive (DANGEROUS)
rmdir dir/                    # Remove empty directory only
find . -name "*.tmp" -delete  # Find and delete

# Create
touch file                    # Create empty file or update timestamp
mkdir dir                     # Create directory
mkdir -p /path/to/nested/dir  # Create with parents
mkdir -m 750 dir              # Create with specific permissions

# Links
ln -s /path/to/target linkname    # Symbolic link
ln source hardlink                 # Hard link
readlink -f symlink                # Resolve symlink to real path
```

### Finding Files

```bash
# find — filesystem search
find /path -name "*.log"                  # By name (glob)
find /path -iname "*.log"                 # Case-insensitive
find /path -type f                        # Files only
find /path -type d                        # Directories only
find /path -type l                        # Symlinks only
find /path -size +100M                    # Larger than 100MB
find /path -size +1G -size -10G          # Size range
find /path -mtime -7                      # Modified in last 7 days
find /path -mtime +30                     # Modified more than 30 days ago
find /path -newer /etc/hosts              # Newer than reference file
find /path -user username                 # Owned by user
find /path -perm 644                      # Exact permissions
find /path -perm /u+s                     # SUID files
find /path -empty                         # Empty files/dirs
find /path -maxdepth 2                    # Limit recursion depth
find /path -name "*.log" -exec rm {} \;  # Execute command on results
find /path -name "*.log" -exec rm {} +   # Batch execution (faster)
find /path -name "*.log" | xargs rm      # xargs version

# locate — index-based (faster but not real-time)
sudo updatedb                             # Update index
locate filename                           # Search index
locate -i filename                        # Case-insensitive
locate --regex "\.py$"                    # Regex

# which / whereis
which python3                             # Path of executable in PATH
whereis nginx                             # Binaries, man pages, source
type ls                                   # Shell's interpretation of name
```

### Viewing Files

```bash
cat file                      # Print entire file
cat -n file                   # With line numbers
cat -A file                   # Show non-printing chars (tabs, line endings)

less file                     # Page viewer (preferred over more)
# less navigation: j/k (lines), d/u (half page), g/G (start/end),
#                  /pattern (search), n/N (next/prev match), q (quit)

head -n 20 file               # First 20 lines
tail -n 20 file               # Last 20 lines
tail -f file                  # Follow (live tail) — logs
tail -F file                  # Follow with retry (survives rotation)

wc -l file                    # Line count
wc -w file                    # Word count
wc -c file                    # Byte count
wc -m file                    # Character count

file /path/to/file            # Determine file type
stat file                     # Detailed file metadata
xxd file | head               # Hex dump
od -c file | head             # Octal dump with chars
strings binary                # Extract printable strings from binary

# Compressed files
zcat file.gz                  # Cat compressed file
zless file.gz                 # Less for compressed file
bzcat file.bz2                # bzip2 equivalent
xzcat file.xz                 # xz equivalent
```

### Archives

```bash
# tar
tar -czf archive.tar.gz dir/          # Create gzip compressed
tar -cjf archive.tar.bz2 dir/         # Create bzip2 compressed
tar -cJf archive.tar.xz dir/          # Create xz compressed
tar -czf archive.tar.gz file1 file2   # Multiple items
tar -xzf archive.tar.gz               # Extract gzip
tar -xzf archive.tar.gz -C /dest/     # Extract to directory
tar -tzf archive.tar.gz               # List contents
tar -xzf archive.tar.gz file.txt      # Extract specific file

# zip
zip archive.zip file1 file2
zip -r archive.zip dir/               # Recursive
unzip archive.zip
unzip archive.zip -d /dest/           # Extract to directory
unzip -l archive.zip                  # List contents

# Permissions-preserving backup
tar -czpf backup.tar.gz --acls --xattrs /path/
```

---

## 9. Text Processing & Pipelines

### grep

```bash
grep "pattern" file
grep -i "pattern" file         # Case-insensitive
grep -r "pattern" /path/       # Recursive
grep -l "pattern" /path/       # Files containing match (names only)
grep -L "pattern" /path/       # Files NOT containing match
grep -n "pattern" file         # Show line numbers
grep -c "pattern" file         # Count matching lines
grep -v "pattern" file         # Invert match (non-matching lines)
grep -w "word" file            # Whole word match
grep -x "line" file            # Whole line match
grep -A 3 "pattern" file       # 3 lines after match
grep -B 3 "pattern" file       # 3 lines before match
grep -C 3 "pattern" file       # 3 lines before AND after
grep -E "regex" file           # Extended regex (egrep)
grep -P "regex" file           # Perl regex
grep -o "pattern" file         # Print only matching part
grep -m 5 "pattern" file       # Stop after 5 matches
grep --color=always "pattern" file | less -R

# Practical
grep "ERROR" /var/log/syslog | grep -v "harmless"
grep -r "TODO\|FIXME" /src/ --include="*.py"
grep -rn "import os" /project/ | head -20
journalctl | grep -E "failed|error" -i
```

### awk

```bash
# awk 'pattern { action }' file
awk '{print $1}' file          # Print first field (space-delimited)
awk '{print $NF}' file         # Print last field
awk -F: '{print $1}' /etc/passwd  # Custom delimiter
awk 'NR==5' file               # Print line 5
awk 'NR>=5 && NR<=10' file     # Print lines 5-10
awk '/pattern/' file           # Lines matching pattern
awk '/start/,/end/' file       # Lines between start and end patterns
awk '{sum += $3} END {print sum}' file  # Sum column 3
awk '{print $2, $1}' file      # Reorder columns
awk 'NF > 3' file              # Lines with more than 3 fields
awk '$3 > 100 {print $1, $3}' file  # Conditional
awk 'BEGIN{FS=":"; OFS="\t"} {print $1,$3}' /etc/passwd

# Practical examples
ps aux | awk '{print $1, $2, $11}' | head  # User, PID, command
df -h | awk '$5 > 80 {print $6, $5}'       # Disks over 80% full
awk -F: '$3 >= 1000 {print $1}' /etc/passwd  # List non-system users
```

### sed

```bash
sed 's/old/new/' file          # Replace first occurrence per line
sed 's/old/new/g' file         # Replace all occurrences
sed 's/old/new/i' file         # Case-insensitive replace
sed -i 's/old/new/g' file      # In-place edit
sed -i.bak 's/old/new/g' file  # In-place with backup
sed -n '5p' file               # Print line 5
sed -n '5,10p' file            # Print lines 5-10
sed '5d' file                  # Delete line 5
sed '/pattern/d' file          # Delete lines matching pattern
sed -n '/start/,/end/p' file   # Print between patterns
sed 's/^/prefix/' file         # Add prefix to each line
sed 's/$/ suffix/' file        # Add suffix to each line
sed '/pattern/a\new line' file # Append line after match
sed '/pattern/i\new line' file # Insert line before match

# Multi-command
sed -e 's/foo/bar/g' -e 's/baz/qux/g' file
sed -f script.sed file         # Read commands from file
```

### sort, uniq, cut, tr

```bash
# sort
sort file                      # Alphabetical sort
sort -r file                   # Reverse sort
sort -n file                   # Numeric sort
sort -k2 file                  # Sort by field 2
sort -k2,2 -k1,1 file          # Sort by field 2, then 1
sort -t: -k3 -n /etc/passwd    # Sort passwd by UID
sort -u file                   # Sort and remove duplicates

# uniq (requires sorted input)
sort file | uniq               # Remove duplicates
sort file | uniq -c            # Count occurrences
sort file | uniq -d            # Only duplicate lines
sort file | uniq -u            # Only unique lines (appear once)

# cut
cut -d: -f1 /etc/passwd        # Field 1, colon delimiter
cut -d, -f2,4 file.csv         # Fields 2 and 4
cut -c1-10 file                # Characters 1-10
cut -c-5 file                  # First 5 characters

# tr
tr 'a-z' 'A-Z' < file          # Lowercase to uppercase
tr -d '\r' < file              # Remove carriage returns (Windows line endings)
tr -s ' ' < file               # Squeeze multiple spaces into one
tr -d '[:digit:]' < file       # Remove all digits
echo "hello world" | tr ' ' '\n'  # Replace spaces with newlines

# paste
paste file1 file2              # Merge lines side by side
paste -d, file1 file2          # Custom delimiter
paste -s file                  # Serial: all lines of file on one line
```

### Advanced Pipeline Patterns

```bash
# Process substitution
diff <(ls /dir1) <(ls /dir2)                  # Compare directory listings
comm <(sort file1) <(sort file2)               # Common/unique lines

# tee — write to file AND continue pipeline
command | tee output.log | next_command
command | tee -a output.log                    # Append mode

# xargs — build commands from stdin
find . -name "*.py" | xargs wc -l             # Line count all python files
cat servers.txt | xargs -I{} ssh {} uptime    # SSH to each server
find . -name "*.log" | xargs -P 4 gzip        # Parallel compression

# Column formatting
column -t -s, file.csv                         # CSV to aligned table
ps aux | column -t

# Heredoc
cat << 'EOF' > /etc/myconfig.conf
key=value
another=setting
EOF

# Count lines matching pattern per file
grep -c "ERROR" /var/log/*.log | sort -t: -k2 -nr | head
```

---

## 10. Networking

### Interface Management

```bash
# Show interfaces
ip addr show                   # All interfaces with addresses
ip addr show eth0              # Specific interface
ip link show                   # Link-layer info (MAC, state)
ifconfig -a                    # Legacy (net-tools)

# Configure interface
sudo ip addr add 192.168.1.100/24 dev eth0    # Add IP
sudo ip addr del 192.168.1.100/24 dev eth0    # Remove IP
sudo ip link set eth0 up                       # Bring up
sudo ip link set eth0 down                     # Bring down
sudo ip link set eth0 mtu 9000                 # Set MTU (jumbo frames)

# Routes
ip route show                  # Routing table
ip route add default via 192.168.1.1           # Default gateway
ip route add 10.0.0.0/8 via 10.1.1.1          # Static route
ip route del 10.0.0.0/8                        # Remove route

# DNS
cat /etc/resolv.conf           # DNS servers
resolvectl status              # systemd-resolved status
nslookup hostname              # DNS lookup (legacy)
dig hostname                   # DNS lookup (detailed)
dig hostname +short            # Just the IP
dig @8.8.8.8 hostname          # Query specific DNS server
dig -x 1.2.3.4                 # Reverse DNS lookup
host hostname                  # Simple DNS lookup
```

### Connectivity & Diagnostics

```bash
# Ping
ping -c 4 hostname             # 4 packets
ping -i 0.2 hostname           # 200ms interval
ping -s 1472 hostname          # Custom packet size (MTU test)
ping6 hostname                 # IPv6

# Traceroute
traceroute hostname            # UDP by default
traceroute -T hostname         # TCP
traceroute -I hostname         # ICMP
mtr hostname                   # Combined ping + traceroute (live)

# Port scanning / connectivity
nc -zv hostname 80             # TCP connect test
nc -zuv hostname 53            # UDP test
nc -l 8080                     # Listen on port 8080
telnet hostname 80             # Legacy TCP connect test
curl -v http://hostname        # HTTP with verbose headers
wget -q -O- http://hostname    # Fetch URL

# Network statistics
ss -tuln                       # Listening TCP/UDP (no names)
ss -tulnp                      # Include process name/PID
ss -s                          # Summary statistics
ss -t state established        # All established TCP
ss -t dst 10.0.0.1             # Connections to specific IP
netstat -tulnp                 # Legacy (requires net-tools)
netstat -s                     # Protocol statistics

# Bandwidth / throughput
iperf3 -s                      # Server mode
iperf3 -c server_ip            # Client mode (TCP)
iperf3 -c server_ip -u -b 100M # UDP bandwidth test

# DNS debugging
systemd-resolve --statistics   # Cache statistics
resolvectl flush-caches        # Flush DNS cache
```

### SSH

```bash
# Connect
ssh user@hostname              # Basic
ssh -p 2222 user@hostname      # Custom port
ssh -i ~/.ssh/key user@hostname  # Specific key
ssh -A user@hostname           # Forward agent
ssh -X user@hostname           # X11 forwarding

# Tunnels
ssh -L 8080:localhost:80 user@host   # Local forward: local:8080 → host:80
ssh -R 9090:localhost:3000 user@host # Remote forward: host:9090 → local:3000
ssh -D 1080 user@host                # Dynamic (SOCKS proxy)
ssh -N user@host                     # No command (tunnels only)

# Key management
ssh-keygen -t ed25519 -C "comment"   # Generate ED25519 key (preferred)
ssh-keygen -t rsa -b 4096            # RSA 4096 key
ssh-copy-id user@hostname            # Copy public key to server
cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys  # Manual copy

# Config file: ~/.ssh/config
Host myserver
    HostName 192.168.1.100
    User deploy
    Port 2222
    IdentityFile ~/.ssh/deploy_key
    ServerAliveInterval 60

# scp / rsync
scp file user@host:/dest/            # Copy to remote
scp -r dir/ user@host:/dest/         # Recursive
rsync -avz source/ user@host:/dest/  # Sync (preferred: resumable)
rsync -avz --delete source/ dest/    # Mirror (delete extraneous)
rsync -avz -e "ssh -p 2222" src/ user@host:/dest/

# SSH hardening (/etc/ssh/sshd_config)
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowUsers deploy admin
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

### Firewall (UFW & iptables)

```bash
# UFW (Uncomplicated Firewall) — Ubuntu default
sudo ufw status verbose        # Current rules
sudo ufw enable                # Enable firewall
sudo ufw disable               # Disable firewall
sudo ufw reset                 # Reset to defaults

sudo ufw default deny incoming  # Block all inbound
sudo ufw default allow outgoing # Allow all outbound

sudo ufw allow ssh              # Allow SSH (port 22)
sudo ufw allow 80/tcp           # Allow HTTP
sudo ufw allow 443/tcp          # Allow HTTPS
sudo ufw allow 8080:8090/tcp    # Port range
sudo ufw allow from 10.0.0.0/8 to any port 5432  # Source-based rule
sudo ufw deny 23                # Deny telnet
sudo ufw delete allow 80/tcp   # Remove a rule
sudo ufw logging on             # Enable logging

# iptables (underlying mechanism)
sudo iptables -L -n -v          # List all rules with counters
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 22 -s 10.0.0.0/8 -j ACCEPT
sudo iptables -A INPUT -j DROP                    # Drop everything else
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Save/restore iptables
sudo iptables-save > /etc/iptables/rules.v4
sudo iptables-restore < /etc/iptables/rules.v4
```

### Network Configuration (Netplan — Ubuntu 18.04+)

```yaml
# /etc/netplan/01-network.yaml

# DHCP (default)
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: true

# Static IP
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      addresses: [192.168.1.100/24]
      gateway4: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]

# Bonding
network:
  bonds:
    bond0:
      interfaces: [eth0, eth1]
      parameters:
        mode: active-backup
```

```bash
sudo netplan apply              # Apply netplan configuration
sudo netplan try                # Apply with auto-revert if no confirm
sudo netplan generate           # Generate backend config
```

---

## 11. Package Management

### APT (Advanced Package Tool)

```bash
# Repository management
sudo apt update                              # Refresh package index
sudo apt upgrade                             # Upgrade installed packages
sudo apt full-upgrade                        # Upgrade + handle dependency changes
sudo apt dist-upgrade                        # Same as full-upgrade (legacy name)
sudo apt autoremove                          # Remove unused dependencies
sudo apt autoclean                           # Clear outdated downloaded packages
sudo apt clean                               # Clear entire package cache

# Search and info
apt search keyword                           # Search packages
apt show package                             # Package details
apt list --installed                         # All installed packages
apt list --installed | grep package          # Search installed
apt list --upgradable                        # Upgradable packages
dpkg -l | grep package                       # Check if installed
dpkg -l | awk '$1=="ii" {print $2}'          # All installed (dpkg format)

# Install / Remove
sudo apt install package
sudo apt install package=1.2.3               # Specific version
sudo apt install -y package                  # Skip confirmation
sudo apt install --no-install-recommends package  # Minimal install
sudo apt remove package                      # Remove (keep config)
sudo apt purge package                       # Remove + config files
sudo apt install -f                          # Fix broken dependencies

# APT sources
cat /etc/apt/sources.list                    # Main sources
ls /etc/apt/sources.list.d/                  # Additional PPAs/repos

# Add PPA
sudo add-apt-repository ppa:user/repo
sudo apt update && sudo apt install package

# Add external repo
curl -fsSL https://repo.example.com/key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/example.gpg
echo "deb [signed-by=/usr/share/keyrings/example.gpg] https://repo.example.com/apt stable main" | sudo tee /etc/apt/sources.list.d/example.list
sudo apt update

# Hold a package at current version
sudo apt-mark hold package
sudo apt-mark unhold package
apt-mark showhold

# Download without installing
apt download package
apt-get source package         # Download source package
```

### dpkg (Low-Level Package Tool)

```bash
sudo dpkg -i package.deb        # Install .deb file
sudo dpkg -r package            # Remove package
sudo dpkg -P package            # Purge package
dpkg -l                         # List all installed packages
dpkg -l package                 # Status of specific package
dpkg -L package                 # List files installed by package
dpkg -S /path/to/file           # Which package owns a file
dpkg -s package                 # Package status/info
dpkg --get-selections           # All package selections
dpkg-reconfigure package        # Re-run post-install configuration
```

### Snap (Universal Packages)

```bash
snap find keyword               # Search snap store
snap install package            # Install snap
snap install package --classic  # Install with classic confinement
snap remove package             # Remove snap
snap list                       # Installed snaps
snap info package               # Package details
snap refresh package            # Update snap
snap refresh                    # Update all snaps
snap revert package             # Rollback to previous version
snap enable package             # Enable disabled snap
snap disable package            # Disable snap
```

---

## 12. Disk, Filesystem & Storage

### Disk Operations

```bash
# List block devices
lsblk                           # Tree view of block devices
lsblk -f                        # Include filesystem info
fdisk -l                        # List all disk partitions
parted -l                       # More modern partition info

# Disk usage
df -h                           # Disk usage per filesystem
df -i                           # Inode usage per filesystem
du -sh /path                    # Size of directory
du -sh /path/*                  # Size of each item in path
du -sh /* 2>/dev/null | sort -h # Sort by size (find space hogs)
du -ah /path | sort -h | tail -20  # 20 largest items

# SMART status (disk health)
sudo smartctl -a /dev/sda
sudo smartctl -t short /dev/sda   # Run short self-test

# I/O statistics
iostat -x 1 5                   # Extended I/O stats every 1s, 5 times
iotop                           # Real-time I/O by process
```

### Partitioning

```bash
# fdisk (MBR disks)
sudo fdisk /dev/sdb
# Commands inside fdisk:
# n — new partition
# d — delete partition
# p — print partition table
# t — change partition type
# w — write and exit
# q — quit without saving

# gdisk (GPT disks)
sudo gdisk /dev/sdb

# parted (supports both MBR and GPT)
sudo parted /dev/sdb mklabel gpt
sudo parted /dev/sdb mkpart primary ext4 0% 100%
```

### Filesystem Operations

```bash
# Format
sudo mkfs.ext4 /dev/sdb1              # Create ext4 filesystem
sudo mkfs.ext4 -L "DATA" /dev/sdb1   # With label
sudo mkfs.xfs /dev/sdb1              # XFS (default on RHEL)
sudo mkswap /dev/sdb2                # Swap partition
sudo swapon /dev/sdb2                # Enable swap

# Mount
sudo mount /dev/sdb1 /mnt/data
sudo mount -t ext4 /dev/sdb1 /mnt/data
sudo mount -o ro /dev/sdb1 /mnt/data  # Read-only
sudo mount -o remount,rw /mnt/data   # Remount read-write
sudo umount /mnt/data
sudo umount -l /mnt/data              # Lazy unmount (busy filesystem)

# Permanent mounts: /etc/fstab
# device  mountpoint  fstype  options  dump  pass
/dev/sdb1  /data  ext4  defaults,noatime  0  2
UUID=abc123  /data  ext4  defaults  0  2  # Prefer UUID
tmpfs  /tmp  tmpfs  defaults,size=2G  0  0

# Get UUID
sudo blkid /dev/sdb1
ls -la /dev/disk/by-uuid/

# Check / repair filesystem (unmounted)
sudo fsck -n /dev/sdb1          # Check only (no repair)
sudo fsck -y /dev/sdb1          # Repair automatically
sudo e2fsck -f /dev/sdb1        # Force check ext2/3/4
sudo xfs_repair /dev/sdb1       # Repair XFS

# ext4 tuning
sudo tune2fs -l /dev/sdb1       # Show filesystem parameters
sudo tune2fs -m 1 /dev/sdb1     # Reduce reserved space to 1%
sudo tune2fs -L "DATA" /dev/sdb1  # Set label
```

### LVM (Logical Volume Manager)

```bash
# Physical Volumes
sudo pvcreate /dev/sdb1 /dev/sdc1   # Initialize PVs
pvdisplay                            # Show PVs
pvs                                  # Summary

# Volume Groups
sudo vgcreate datavg /dev/sdb1 /dev/sdc1  # Create VG
vgdisplay datavg                     # Show VG
vgs                                  # Summary
sudo vgextend datavg /dev/sdd1       # Add PV to VG

# Logical Volumes
sudo lvcreate -L 50G -n datalv datavg  # Create 50G LV
sudo lvcreate -l 100%FREE -n datalv datavg  # Use all free space
lvdisplay                             # Show LVs
lvs                                   # Summary
sudo lvextend -L +20G /dev/datavg/datalv   # Extend by 20G
sudo lvextend -l +100%FREE /dev/datavg/datalv  # Use remaining space
sudo resize2fs /dev/datavg/datalv     # Resize filesystem after extending
sudo lvreduce -L 30G /dev/datavg/datalv    # Shrink (unmount first!)

# Snapshots
sudo lvcreate -L 5G -s -n snap /dev/datavg/datalv  # Snapshot
sudo lvremove /dev/datavg/snap        # Remove snapshot
```

---

## 13. Systemd & Service Management

### systemd Architecture

```
systemd (PID 1)
├── Units (service, socket, timer, mount, device, target, path, scope, slice)
├── Targets (groups of units — replaces SysV runlevels)
├── Journals (journald — binary log storage)
├── Login (logind — user sessions)
├── Network (networkd — optional)
└── Resolved (DNS resolution — optional)
```

### Unit File Types

| Type | Extension | Description |
|------|-----------|-------------|
| Service | .service | Background daemon |
| Socket | .socket | IPC / network socket activation |
| Timer | .timer | Cron-like scheduled execution |
| Mount | .mount | Filesystem mount |
| Automount | .automount | On-demand mount |
| Target | .target | Group of units (sync points) |
| Path | .path | Watch filesystem path |
| Slice | .slice | cgroup resource management |
| Device | .device | Kernel device |

### Service Management Commands

```bash
# Status and inspection
systemctl status nginx                  # Service status + recent logs
systemctl is-active nginx               # active / inactive / failed
systemctl is-enabled nginx              # enabled / disabled
systemctl is-failed nginx               # Whether unit is in failed state
systemctl list-units --type=service     # All loaded service units
systemctl list-units --type=service --state=running  # Running only
systemctl list-units --type=service --state=failed   # Failed units
systemctl list-unit-files --type=service  # All installed unit files
systemctl show nginx                    # All properties of unit
systemctl cat nginx                     # Show unit file(s)

# Start / Stop / Restart
sudo systemctl start nginx
sudo systemctl stop nginx
sudo systemctl restart nginx            # Stop then start
sudo systemctl reload nginx             # Reload config (SIGHUP)
sudo systemctl reload-or-restart nginx  # Prefer reload if supported

# Enable / Disable (persist across reboots)
sudo systemctl enable nginx             # Enable at boot
sudo systemctl disable nginx            # Disable at boot
sudo systemctl enable --now nginx       # Enable and start immediately
sudo systemctl disable --now nginx      # Disable and stop immediately

# Masking (prevent any start)
sudo systemctl mask nginx               # Prevent start (even manually)
sudo systemctl unmask nginx             # Remove mask

# Reload unit files
sudo systemctl daemon-reload            # REQUIRED after editing unit files

# Boot analysis
systemd-analyze                         # Total boot time
systemd-analyze blame                   # Per-unit time
systemd-analyze critical-chain          # Critical path to default target
systemd-analyze plot > boot.svg         # Visual boot timeline

# Dependencies
systemctl list-dependencies nginx       # What nginx depends on
systemctl list-dependencies --reverse nginx  # What depends on nginx
```

### Writing a systemd Service Unit

```ini
# /etc/systemd/system/myapp.service

[Unit]
Description=My Application
Documentation=https://example.com/docs
After=network.target postgresql.service
Requires=postgresql.service          # Hard dependency (fail if not running)
Wants=redis.service                  # Soft dependency (start if possible)

[Service]
Type=simple                          # simple|forking|oneshot|notify|dbus|idle
User=myapp
Group=myapp
WorkingDirectory=/opt/myapp
ExecStart=/opt/myapp/bin/myapp --config /etc/myapp/config.yaml
ExecStop=/bin/kill -TERM $MAINPID
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure                   # always|on-failure|on-abnormal|no
RestartSec=5                         # Wait 5s before restarting
StartLimitIntervalSec=60             # Give up after 60s
StartLimitBurst=3                    # If failed 3 times within interval

# Environment
Environment=APP_ENV=production
EnvironmentFile=/etc/myapp/env       # Load from file (KEY=VALUE format)

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/myapp /var/log/myapp

# Resource limits
LimitNOFILE=65535
MemoryMax=2G
CPUQuota=80%

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=myapp

[Install]
WantedBy=multi-user.target           # Activated by this target
```

### Service Types

| Type | When to Use | Behaviour |
|------|-------------|-----------|
| `simple` | Most daemons | Main process is ExecStart |
| `forking` | Old daemons that fork | systemd tracks child PID |
| `oneshot` | One-time tasks | Runs, exits, considered active |
| `notify` | Daemons with sd_notify | Sends READY=1 when ready |
| `dbus` | D-Bus services | Ready when name appears on bus |
| `idle` | Background tasks | Wait until other boot jobs done |

### Socket Activation

```ini
# /etc/systemd/system/myapp.socket
[Unit]
Description=My App Socket

[Socket]
ListenStream=/run/myapp.sock    # Unix socket
ListenStream=8080               # TCP port
Accept=false                    # Pass socket to service

[Install]
WantedBy=sockets.target
```

```ini
# /etc/systemd/system/myapp.service (socket-activated)
[Unit]
Description=My App (socket-activated)

[Service]
ExecStart=/opt/myapp/bin/myapp
StandardInput=socket
```

### Timer Units (Scheduled Tasks)

```ini
# /etc/systemd/system/backup.timer
[Unit]
Description=Daily backup timer

[Timer]
OnCalendar=*-*-* 02:00:00       # Daily at 2am
RandomizedDelaySec=300           # Add up to 5min random delay
Persistent=true                  # Run if last run was missed

[Install]
WantedBy=timers.target
```

```ini
# /etc/systemd/system/backup.service
[Unit]
Description=Backup service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup.sh
```

```bash
systemctl list-timers            # All timers and next run time
systemctl enable --now backup.timer
```

### journald — Logging

```bash
# View logs
journalctl                          # All logs (oldest first)
journalctl -r                       # Newest first
journalctl -f                       # Follow (like tail -f)
journalctl -n 50                    # Last 50 lines
journalctl -u nginx                 # Logs for nginx unit
journalctl -u nginx -f              # Follow nginx logs
journalctl --since "2024-01-01"     # Since date
journalctl --since "1 hour ago"     # Since relative time
journalctl --until "2024-01-02"     # Until date
journalctl --since "09:00" --until "10:00"
journalctl -p err                   # Error and above (emerg alert crit err)
journalctl -p warning               # Warning and above
journalctl _PID=1234                # Logs from specific PID
journalctl _UID=1000                # Logs from specific user
journalctl -k                       # Kernel messages (dmesg equivalent)
journalctl -b                       # Current boot
journalctl -b -1                    # Previous boot
journalctl --list-boots             # All available boots
journalctl -o json-pretty           # JSON output
journalctl -o verbose               # All fields

# Disk usage
journalctl --disk-usage
sudo journalctl --vacuum-size=1G    # Keep only 1G of logs
sudo journalctl --vacuum-time=30d   # Keep only 30 days of logs

# Configuration: /etc/systemd/journald.conf
# Storage=persistent                 # Keep logs across reboots
# SystemMaxUse=1G                    # Max disk usage
# MaxRetentionSec=30day              # Max age
```

---

## 14. Setting Up Common Services

### Nginx (Web Server / Reverse Proxy)

```bash
sudo apt install nginx
sudo systemctl enable --now nginx
sudo ufw allow 'Nginx Full'

# Configuration structure
/etc/nginx/nginx.conf              # Main config
/etc/nginx/sites-available/        # Available vhosts (not active)
/etc/nginx/sites-enabled/          # Symlinks to active vhosts
/etc/nginx/conf.d/                 # Global snippets
/var/www/html/                     # Default document root
/var/log/nginx/access.log          # Access logs
/var/log/nginx/error.log           # Error logs
```

```nginx
# /etc/nginx/sites-available/myapp

# HTTP → HTTPS redirect
server {
    listen 80;
    server_name example.com www.example.com;
    return 301 https://$host$request_uri;
}

# HTTPS + Reverse Proxy
server {
    listen 443 ssl http2;
    server_name example.com www.example.com;

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;

    # Proxy to backend
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Static files
    location /static/ {
        alias /opt/myapp/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        proxy_pass http://127.0.0.1:3000;
    }
}

# Load balancing upstream
upstream backend {
    least_conn;
    server 10.0.0.1:3000 weight=5;
    server 10.0.0.2:3000 weight=5;
    server 10.0.0.3:3000 backup;
    keepalive 32;
}
```

```bash
sudo nginx -t                     # Test configuration
sudo systemctl reload nginx       # Reload without downtime
sudo ln -s /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled/

# Let's Encrypt SSL
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d example.com -d www.example.com
sudo certbot renew --dry-run      # Test auto-renewal
```

### PostgreSQL

```bash
sudo apt install postgresql postgresql-contrib
sudo systemctl enable --now postgresql

# Connect as postgres superuser
sudo -u postgres psql

# psql commands
CREATE USER myapp WITH PASSWORD 'secret';
CREATE DATABASE myappdb OWNER myapp;
GRANT ALL PRIVILEGES ON DATABASE myappdb TO myapp;
\l                                # List databases
\du                               # List users
\q                                # Quit

# Connect to a specific database
psql -U myapp -d myappdb -h localhost

# Key config files
/etc/postgresql/<version>/main/postgresql.conf   # Server config
/etc/postgresql/<version>/main/pg_hba.conf       # Auth config
```

```
# /etc/postgresql/14/main/pg_hba.conf
# TYPE  DATABASE  USER      ADDRESS       METHOD
local   all       postgres               peer
local   all       all                    peer
host    myappdb   myapp     127.0.0.1/32 scram-sha-256
host    myappdb   myapp     ::1/128      scram-sha-256
```

```bash
# postgresql.conf tuning
max_connections = 200
shared_buffers = 1GB              # 25% of RAM
effective_cache_size = 3GB        # 75% of RAM
work_mem = 16MB
maintenance_work_mem = 256MB
wal_level = replica               # For replication
max_wal_senders = 3
```

### MySQL / MariaDB

```bash
sudo apt install mysql-server
sudo systemctl enable --now mysql
sudo mysql_secure_installation    # Secure initial setup

sudo mysql -u root -p

CREATE DATABASE mydb;
CREATE USER 'myapp'@'localhost' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON mydb.* TO 'myapp'@'localhost';
FLUSH PRIVILEGES;

# Config: /etc/mysql/mysql.conf.d/mysqld.cnf
# bind-address = 0.0.0.0   # Allow remote connections
# max_connections = 200
# innodb_buffer_pool_size = 1G   # Key performance setting
```

### Redis

```bash
sudo apt install redis-server
sudo systemctl enable --now redis-server

# /etc/redis/redis.conf
bind 127.0.0.1                    # Bind address
requirepass yourpassword          # Enable password
maxmemory 2gb                     # Memory limit
maxmemory-policy allkeys-lru      # Eviction policy
save 900 1                        # RDB snapshot
appendonly yes                    # AOF persistence

redis-cli ping                    # Test connectivity
redis-cli -a password info        # Server info
redis-cli -a password monitor     # Live command monitor
```

### Docker

```bash
# Install Docker Engine (Ubuntu)
sudo apt remove docker docker-engine docker.io containerd runc
sudo apt install -y ca-certificates curl gnupg
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
echo "deb [signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update && sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER     # Add user to docker group

# Container lifecycle
docker run -d --name mycontainer -p 8080:80 nginx
docker start / stop / restart / rm mycontainer
docker exec -it mycontainer bash
docker logs -f mycontainer
docker inspect mycontainer
docker ps                         # Running containers
docker ps -a                      # All containers
docker images                     # Local images
docker pull ubuntu:22.04
docker rmi image:tag

# Docker Compose
docker compose up -d              # Start all services
docker compose down               # Stop and remove containers
docker compose logs -f service    # Follow service logs
docker compose ps                 # Service status
docker compose exec service bash  # Shell into service

# System cleanup
docker system prune               # Remove unused everything
docker system df                  # Disk usage
```

### UFW + Fail2Ban (Security Layer)

```bash
sudo apt install fail2ban

# /etc/fail2ban/jail.local
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
banaction = ufw

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
logpath = /var/log/nginx/error.log

sudo systemctl enable --now fail2ban
sudo fail2ban-client status        # Overview
sudo fail2ban-client status sshd   # SSH jail status
sudo fail2ban-client set sshd unbanip 1.2.3.4  # Unban IP
```

---

## 15. Cron & Scheduled Tasks

### Cron Syntax

```
# ┌─── Minute (0-59)
# │  ┌── Hour (0-23)
# │  │  ┌─ Day of Month (1-31)
# │  │  │  ┌ Month (1-12)
# │  │  │  │  ┌ Day of Week (0-7, 0&7=Sunday)
# │  │  │  │  │
  *  *  *  *  *  command

# Examples
0 2 * * *          /opt/scripts/backup.sh     # Daily at 2:00 AM
*/5 * * * *        /opt/scripts/check.sh      # Every 5 minutes
0 */6 * * *        /opt/scripts/sync.sh       # Every 6 hours
0 9 * * 1-5        /opt/scripts/report.sh     # 9 AM Mon-Fri
0 0 1 * *          /opt/scripts/monthly.sh    # First of each month
@reboot            /opt/scripts/startup.sh    # On reboot
@daily             /opt/scripts/daily.sh      # Shorthand for 0 0 * * *
@hourly            /opt/scripts/hourly.sh     # Shorthand for 0 * * * *
```

### Crontab Management

```bash
crontab -e                         # Edit current user's crontab
crontab -l                         # List current user's crontab
crontab -r                         # Remove current user's crontab
sudo crontab -u username -e        # Edit another user's crontab

# System-wide cron (run as root)
/etc/crontab                       # System crontab (includes username field)
/etc/cron.d/                       # Drop-in cron files
/etc/cron.hourly/                  # Scripts run hourly
/etc/cron.daily/                   # Scripts run daily
/etc/cron.weekly/                  # Scripts run weekly
/etc/cron.monthly/                 # Scripts run monthly

# /etc/crontab format (note username field):
# min hour dom month dow user command
0 * * * * root /usr/local/bin/cleanup.sh

# Cron logs
grep CRON /var/log/syslog
journalctl -u cron
```

---

## 16. Shell & Scripting

### Bash Fundamentals

```bash
#!/usr/bin/env bash
set -euo pipefail                  # Exit on error, unset var, pipe failure
# -e: exit on error
# -u: error on unset variable
# -o pipefail: pipe fails if any command fails

# Variables
NAME="world"
echo "Hello, $NAME"
echo "Hello, ${NAME}!"             # Braces required for disambiguation
readonly CONST="immutable"
unset NAME

# Quoting
echo $NAME                         # Word-split, glob-expand
echo "$NAME"                       # No splitting/globbing (preferred)
echo '$NAME'                       # Literal — no expansion
echo "Value: ${NAME:-default}"     # Default if unset/empty

# Parameter expansion
${var:-default}    # Use default if unset/empty
${var:=default}    # Assign default if unset/empty
${var:?error}      # Error if unset/empty
${var:+other}      # Use other if var is set
${#var}            # Length of var
${var%suffix}      # Remove shortest suffix match
${var%%suffix}     # Remove longest suffix match
${var#prefix}      # Remove shortest prefix match
${var##prefix}     # Remove longest prefix match
${var/old/new}     # Replace first occurrence
${var//old/new}    # Replace all occurrences
${var^^}           # Uppercase
${var,,}           # Lowercase

# Arrays
arr=(one two three)
echo ${arr[0]}                     # First element
echo ${arr[@]}                     # All elements
echo ${#arr[@]}                    # Array length
arr+=(four)                        # Append
for item in "${arr[@]}"; do echo "$item"; done

# Associative arrays (bash 4+)
declare -A map
map["key"]="value"
echo "${map["key"]}"
for key in "${!map[@]}"; do echo "$key: ${map[$key]}"; done
```

### Control Flow

```bash
# Conditionals
if [[ condition ]]; then
    command
elif [[ condition ]]; then
    command
else
    command
fi

# [[ ]] operators
[[ -f file ]]          # File exists and is regular file
[[ -d dir ]]           # Directory exists
[[ -e path ]]          # Path exists (any type)
[[ -s file ]]          # File exists and non-empty
[[ -r file ]]          # File is readable
[[ -w file ]]          # File is writable
[[ -x file ]]          # File is executable
[[ -L file ]]          # File is symlink
[[ -z "$str" ]]        # String is empty
[[ -n "$str" ]]        # String is non-empty
[[ "$a" == "$b" ]]     # String equality
[[ "$a" != "$b" ]]     # String inequality
[[ "$a" =~ regex ]]    # Regex match
[[ $n -eq 5 ]]         # Numeric equal
[[ $n -ne 5 ]]         # Numeric not equal
[[ $n -lt 5 ]]         # Less than
[[ $n -gt 5 ]]         # Greater than
[[ $n -le 5 ]]         # Less or equal
[[ $n -ge 5 ]]         # Greater or equal
[[ cond1 && cond2 ]]   # AND
[[ cond1 || cond2 ]]   # OR

# Loops
for i in {1..10}; do echo $i; done
for i in $(seq 1 5); do echo $i; done
for file in /etc/*.conf; do echo "$file"; done
for ((i=0; i<10; i++)); do echo $i; done

while [[ condition ]]; do
    command
done

until [[ condition ]]; do
    command
done

# Case
case "$var" in
    pattern1)
        command ;;
    pattern2|pattern3)
        command ;;
    *)
        default ;;
esac
```

### Functions

```bash
function greet() {
    local name="$1"               # Local variable
    local -r count="$2"          # Local readonly
    echo "Hello, ${name}!"
    return 0                      # Exit code
}

# Call
greet "World" 5

# Capture output
result=$(greet "World")

# Error handling
function die() {
    echo "ERROR: $*" >&2
    exit 1
}

function must_run() {
    "$@" || die "Command failed: $*"
}
```

### Robust Script Template

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/var/log/${SCRIPT_NAME%.sh}.log"

log()  { echo "[$(date '+%F %T')] INFO:  $*" | tee -a "$LOG_FILE"; }
warn() { echo "[$(date '+%F %T')] WARN:  $*" | tee -a "$LOG_FILE" >&2; }
die()  { echo "[$(date '+%F %T')] ERROR: $*" | tee -a "$LOG_FILE" >&2; exit 1; }

cleanup() {
    log "Cleanup called"
    # cleanup actions
}
trap cleanup EXIT
trap 'die "Unexpected error on line $LINENO"' ERR

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS] <arg>
Options:
  -h, --help      Show this help
  -v, --verbose   Verbose output
  -n, --dry-run   Dry run mode
EOF
    exit 0
}

main() {
    [[ $# -eq 0 ]] && usage
    
    local verbose=false
    local dry_run=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)    usage ;;
            -v|--verbose) verbose=true; shift ;;
            -n|--dry-run) dry_run=true; shift ;;
            --)           shift; break ;;
            -*)           die "Unknown option: $1" ;;
            *)            break ;;
        esac
    done
    
    log "Script started"
    # Main logic here
}

main "$@"
```

---

## 17. Environment Variables & Configuration

```bash
# View
env                               # All environment variables
printenv                          # Same
printenv PATH                     # Specific variable
echo $HOME                        # In shell

# Set (current session only)
export MY_VAR="value"
export PATH="$PATH:/new/path"

# Persistent (user-level)
# Add to ~/.bashrc or ~/.profile or ~/.bash_profile
echo 'export MY_VAR="value"' >> ~/.bashrc
source ~/.bashrc                  # Reload

# System-wide
/etc/environment                  # Simple KEY=VALUE, not shell syntax
/etc/profile                      # Login shell for all users
/etc/profile.d/*.sh               # Drop-in files

# Service environment
# In systemd unit: Environment= or EnvironmentFile=

# Key environment variables
$HOME          # User's home directory
$USER          # Current user
$SHELL         # Current shell
$PATH          # Executable search path
$PWD           # Current directory
$OLDPWD        # Previous directory
$EDITOR        # Default text editor
$VISUAL        # Visual editor (for curses)
$PAGER         # Default pager (less)
$TERM          # Terminal type
$LANG          # Locale
$TZ            # Timezone (e.g., "America/New_York")
$PS1           # Primary shell prompt
$HISTSIZE      # Number of commands in history
$HISTFILE      # Path to history file
$TMPDIR        # Temporary directory

# Timezone
timedatectl                       # Show current time/tz
timedatectl list-timezones        # Available timezones
sudo timedatectl set-timezone America/New_York
sudo timedatectl set-ntp true     # Enable NTP sync
```

---

## 18. Monitoring & Observability

### System Resource Monitoring

```bash
# CPU
top                               # Interactive (q to quit)
htop                              # Better top
mpstat 1 5                        # Per-CPU stats every 1s, 5 times
mpstat -P ALL 1                   # All CPUs
vmstat 1 10                       # Virtual memory stats
sar -u 1 10                       # CPU usage (sysstat)
uptime                            # Load averages (1, 5, 15 min)
w                                 # Load + logged in users

# Load average interpretation
# Load avg = avg number of runnable + uninterruptible processes
# On 4-core system: load 4.0 = 100% utilization, 8.0 = overloaded

# Memory
free -h                           # Memory overview
cat /proc/meminfo                 # Detailed memory stats
vmstat -s                         # Memory statistics summary
smem -r                           # Per-process memory with PSS
ps aux --sort=-%mem | head        # Top memory consumers

# Disk I/O
iostat -x 1 5                     # Extended I/O stats
iotop -ao                         # Cumulative I/O by process (needs root)
ioping /dev/sda                   # I/O latency
hdparm -t /dev/sda                # Disk throughput test

# Network
iftop                             # Network traffic by connection
nethogs                           # Network traffic by process
nload                             # Network throughput
ss -tulnp                         # Open ports

# All-in-one
dstat                             # Combined CPU/disk/net (apt install dstat)
glances                           # Comprehensive system monitor

# Logs
journalctl -f                     # All system logs (follow)
tail -f /var/log/syslog           # Syslog
tail -f /var/log/auth.log         # Authentication events
dmesg -T --level=err,crit         # Kernel errors with timestamps
dmesg -wT                         # Follow kernel messages
```

### Performance Profiling

```bash
# perf (Linux profiler)
sudo perf top                     # Real-time function-level CPU profiler
sudo perf record -g ./binary      # Record with call graphs
sudo perf report                  # Analyze recording
sudo perf stat ./binary           # Count hardware events

# strace (system call tracer)
strace command                    # Trace all syscalls
strace -e trace=open,read,write command  # Specific syscalls
strace -p <pid>                   # Attach to running process
strace -c command                 # Syscall statistics summary
strace -T command                 # Time spent in each syscall

# ltrace (library call tracer)
ltrace command

# lsof (list open files)
lsof                              # All open files
lsof -p <pid>                     # Open files by process
lsof -u username                  # Open files by user
lsof -i :8080                     # Processes using port 8080
lsof -i TCP                       # All TCP connections
lsof /var/log/syslog              # What has this file open
lsof +D /var/log/                 # All files open in directory

# /proc inspection
cat /proc/loadavg                 # Load averages + running/total threads
cat /proc/pressure/cpu            # PSI (Pressure Stall Information)
cat /proc/pressure/memory
cat /proc/pressure/io
```

---

## 19. Security & Hardening

### System Hardening Checklist

```bash
# 1. Keep system updated
sudo apt update && sudo apt upgrade -y
sudo apt install unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades

# 2. SSH hardening
sudo nano /etc/ssh/sshd_config
# PermitRootLogin no
# PasswordAuthentication no
# MaxAuthTries 3
# AllowUsers youruser
# Protocol 2
sudo systemctl reload sshd

# 3. Firewall
sudo ufw enable
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh

# 4. Fail2Ban
sudo apt install fail2ban
sudo systemctl enable --now fail2ban

# 5. Disable unused services
systemctl list-units --type=service --state=running
sudo systemctl disable --now avahi-daemon cups bluetooth

# 6. Check for SUID/SGID files (reduce attack surface)
find / -perm /4000 -type f 2>/dev/null   # SUID files
find / -perm /2000 -type f 2>/dev/null   # SGID files

# 7. File integrity
sudo apt install aide
sudo aideinit                             # Initialize database
sudo aide --check                         # Check for changes

# 8. Audit framework
sudo apt install auditd
sudo systemctl enable --now auditd
auditctl -w /etc/passwd -p wa -k passwd_changes
auditctl -w /etc/shadow -p wa -k shadow_changes
ausearch -k passwd_changes

# 9. AppArmor (Ubuntu default MAC)
sudo aa-status                            # Current profiles
sudo aa-enforce /etc/apparmor.d/usr.sbin.nginx  # Enforce mode
sudo aa-complain profile                  # Complain mode (log only)

# 10. Check listening ports
ss -tulnp
netstat -tulnp
```

### Useful Security Commands

```bash
# Who logged in when
last -n 20                        # Recent logins
lastb -n 20                       # Failed logins
journalctl -u sshd | grep Failed  # SSH failures

# File permissions audit
find /etc -perm -o+w 2>/dev/null  # World-writable files in /etc
find /home -perm 777 2>/dev/null  # World-writable home files
stat /etc/shadow                   # Should be 640, root:shadow

# Running processes with open ports
ss -tulnp | grep -v '127.0.0.1'   # Non-local listening ports

# Check for rootkits
sudo apt install rkhunter chkrootkit
sudo rkhunter --check
sudo chkrootkit

# SSL/TLS certificate check
openssl s_client -connect hostname:443 -showcerts
openssl x509 -in cert.pem -text -noout
openssl x509 -in cert.pem -noout -dates  # Expiry dates

# GPG
gpg --gen-key                     # Generate key pair
gpg --list-keys                   # List public keys
gpg --list-secret-keys            # List private keys
gpg -e -r recipient file          # Encrypt
gpg -d file.gpg                   # Decrypt
gpg --sign file                   # Sign file
gpg --verify file.sig file        # Verify signature
```

---

## 20. Performance Tuning

### Kernel Parameters (sysctl)

```bash
# View all
sysctl -a
sysctl net.core.somaxconn           # View specific

# Set temporarily
sysctl -w net.core.somaxconn=65535

# Persist: /etc/sysctl.conf or /etc/sysctl.d/99-custom.conf
sudo sysctl -p                       # Apply changes

# Network tuning (high-traffic servers)
net.core.somaxconn = 65535           # Listen queue size
net.core.netdev_max_backlog = 5000   # Input queue for NIC
net.ipv4.tcp_max_syn_backlog = 65535 # SYN backlog
net.ipv4.ip_local_port_range = 1024 65535  # Ephemeral port range
net.ipv4.tcp_fin_timeout = 15        # TIME_WAIT duration (default 60)
net.ipv4.tcp_tw_reuse = 1            # Reuse TIME_WAIT sockets
net.ipv4.tcp_keepalive_time = 300    # Keepalive interval
net.core.rmem_max = 134217728        # Max receive buffer (128MB)
net.core.wmem_max = 134217728        # Max send buffer (128MB)
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# File system
fs.file-max = 2097152                # System-wide max open files
fs.inotify.max_user_watches = 524288 # inotify watches (for IDEs, watchers)

# Memory
vm.swappiness = 10                   # Prefer RAM over swap (0-100)
vm.dirty_ratio = 10                  # Max dirty pages before writeback
vm.dirty_background_ratio = 5        # Background writeback threshold
vm.overcommit_memory = 1             # Allow overcommit (for Redis/Java)
```

### CPU & Process Tuning

```bash
# CPU frequency scaling
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# NUMA (Non-Uniform Memory Access)
numactl --hardware                   # NUMA topology
numactl --cpunodebind=0 --membind=0 command  # Bind to NUMA node 0
numad                                # NUMA daemon for automatic placement

# CPU affinity
taskset -c 0,1 command               # Run on CPUs 0 and 1
taskset -p -c 0-3 <pid>              # Set affinity for running process
```

### Memory Tuning

```bash
# Huge pages
cat /proc/meminfo | grep Huge
echo 1024 | sudo tee /proc/sys/vm/nr_hugepages  # Allocate huge pages
# /etc/sysctl.d/99-hugepages.conf
# vm.nr_hugepages = 1024

# Transparent Huge Pages (THP) — disable for databases
cat /sys/kernel/mm/transparent_hugepage/enabled
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled

# Drop caches (careful — emergency use)
sync && echo 3 | sudo tee /proc/sys/vm/drop_caches
```

---

## 21. Containers & Linux Primitives

### Namespaces (The Foundation of Containers)

| Namespace | Flag | Isolates |
|-----------|------|---------|
| PID | CLONE_NEWPID | Process IDs |
| Network | CLONE_NEWNET | Network interfaces, routing |
| Mount | CLONE_NEWNS | Filesystem mounts |
| UTS | CLONE_NEWUTS | Hostname, domain name |
| IPC | CLONE_NEWIPC | SysV IPC, POSIX message queues |
| User | CLONE_NEWUSER | UID/GID mappings |
| Cgroup | CLONE_NEWCGROUP | cgroup root |
| Time | CLONE_NEWTIME | Boot and monotonic clocks |

```bash
# Inspect namespaces of a process
ls -la /proc/<pid>/ns/
lsns                              # List all namespaces
lsns -t net                       # Network namespaces only
nsenter -t <pid> -n ip addr       # Enter network namespace of process
unshare --pid --fork bash         # Create new PID namespace
```

### cgroups (Resource Control)

```bash
# cgroup v2 (systemd uses this by default on Ubuntu 22.04+)
cat /proc/mounts | grep cgroup
ls /sys/fs/cgroup/

# View per-service cgroup limits
systemctl show nginx | grep -i memory
systemctl show nginx | grep -i cpu

# Set via systemd
sudo systemctl set-property nginx.service MemoryMax=1G
sudo systemctl set-property nginx.service CPUQuota=50%

# Direct cgroup manipulation
echo "1G" > /sys/fs/cgroup/mygroup/memory.max
echo "50000 100000" > /sys/fs/cgroup/mygroup/cpu.max  # 50% of 1 CPU
```

### eBPF (Extended Berkeley Packet Filter)

eBPF lets you run sandboxed programs in the kernel without changing kernel source. Used by modern observability tools (Cilium, Falco, Pixie).

```bash
# BCC tools (sudo apt install bpfcc-tools)
execsnoop-bpfcc                   # Trace new processes
opensnoop-bpfcc                   # Trace file opens
tcpconnect-bpfcc                  # Trace TCP connections
biolatency-bpfcc                  # Block I/O latency histogram
funccount-bpfcc 'vfs_*'           # Count kernel function calls
profile-bpfcc -F 99 30            # CPU flame graph data (30s)

# bpftrace
bpftrace -e 'tracepoint:syscalls:sys_enter_read { @[pid] = count(); }'
bpftrace -e 'kprobe:do_sys_open { printf("%s %s\n", comm, str(arg1)); }'
```

---

## 22. Quick Reference Cards

### Essential One-Liners

```bash
# Find and kill processes
pkill -f "python script.py"
kill $(lsof -t -i:8080)                    # Kill whatever is on port 8080

# Monitor log for pattern
tail -f /var/log/nginx/access.log | grep --line-buffered "404"

# Watch a command
watch -n 2 "ss -tulnp | grep nginx"        # Refresh every 2s

# Disk space by directory (sorted)
du -sh /* 2>/dev/null | sort -h

# Find large files
find / -type f -size +1G 2>/dev/null | sort -k5 -h

# Count TCP connections by state
ss -tan | awk 'NR>1 {print $1}' | sort | uniq -c | sort -rn

# Count requests per IP from nginx log
awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head

# Top 10 CPU-consuming processes
ps aux --sort=-%cpu | head -11

# Top 10 memory-consuming processes
ps aux --sort=-%mem | head -11

# Recent failed systemd services
systemctl list-units --state=failed

# All open ports
ss -tulnp | awk '{print $1, $5}' | sort -u

# Check if port is open on remote host
timeout 3 bash -c ">/dev/tcp/hostname/80" && echo open || echo closed

# Colorized diff between two commands
diff <(command1) <(command2) | colordiff

# Base64 encode/decode
echo "hello" | base64
echo "aGVsbG8K" | base64 -d

# HTTP request with timing
curl -o /dev/null -s -w "DNS: %{time_namelookup}\nConnect: %{time_connect}\nTTFB: %{time_starttransfer}\nTotal: %{time_total}\n" http://example.com

# Generate random password
openssl rand -base64 32
tr -dc 'A-Za-z0-9!@#$%' < /dev/urandom | head -c 20
```

### Service Types Summary

| Service | Port | Config Location | Key Command |
|---------|------|-----------------|-------------|
| SSH | 22 | /etc/ssh/sshd_config | systemctl reload sshd |
| HTTP/Nginx | 80/443 | /etc/nginx/ | nginx -t && systemctl reload nginx |
| PostgreSQL | 5432 | /etc/postgresql/ | systemctl restart postgresql |
| MySQL | 3306 | /etc/mysql/ | systemctl restart mysql |
| Redis | 6379 | /etc/redis/ | systemctl restart redis-server |
| Docker | 2376 | /etc/docker/ | systemctl restart docker |
| Cron | - | /etc/crontab | systemctl restart cron |
| UFW | - | /etc/ufw/ | ufw reload |

### Troubleshooting Decision Tree

```
Service not responding?
├── Is it running?          → systemctl status <service>
├── Port listening?         → ss -tulnp | grep <port>
├── Firewall blocking?      → ufw status; iptables -L
├── Process resources?      → top; ulimit -a; cat /proc/<pid>/status
├── Logs say what?          → journalctl -u <service> -n 100
├── Disk full?              → df -h; du -sh /*
├── Memory pressure?        → free -h; vmstat 1 5; dmesg | grep -i oom
└── Network reachable?      → ping; traceroute; nc -zv host port

High CPU?
├── Which process?          → top → P (sort by CPU)
├── What syscalls?          → strace -p <pid> -c
├── Kernel or user?         → top → look at %sy vs %us
└── Profile it              → perf top

High memory?
├── What's using it?        → ps aux --sort=-%mem | head
├── Any memory leak?        → watch -n 5 "cat /proc/<pid>/status | grep VmRSS"
└── OOM killing?            → dmesg | grep -i oom
```

### Key Directories Quick Ref

| Path | Purpose |
|------|---------|
| /etc/systemd/system/ | Custom unit files (override /lib/systemd/system/) |
| /lib/systemd/system/ | Package-installed unit files |
| /etc/ssh/sshd_config | SSH server configuration |
| /etc/nginx/sites-enabled/ | Active nginx vhosts |
| /etc/apt/sources.list.d/ | APT repository configs |
| /var/log/ | All system logs |
| /run/ | Runtime data (PIDs, sockets) |
| /proc/sys/ | Live kernel tunables (sysctl) |
| /sys/fs/cgroup/ | cgroup v2 hierarchy |
| ~/.ssh/ | User SSH keys and config |

---

## FAANG Interview Callouts

**When asked about Linux in system design:**
- "We'd run this on Linux kernel 5.x+ for io_uring support — eliminates copy overhead for high-throughput I/O"
- "For 10K concurrent connections, we tune `net.core.somaxconn`, `fs.file-max`, and `ulimit -n` on each node"
- "Container isolation uses kernel namespaces and cgroups — same kernel, different view"
- "Observability via eBPF probes — zero instrumentation overhead, production-safe"

**Principal engineer depth signals:**
- Know the difference between `Restart=on-failure` and `Restart=always` and when each applies
- Know why `D` state processes cannot be killed (uninterruptible kernel wait)
- Know that `SIGKILL` bypasses signal handlers but the kernel still runs cleanup on process table entry
- Know that socket activation allows zero-downtime binary upgrades (new process inherits socket)
- Know the OOM killer score calculation and how to protect critical processes
- Know that `epoll` (edge-triggered) is the foundation of nginx, Node.js, Redis event loops

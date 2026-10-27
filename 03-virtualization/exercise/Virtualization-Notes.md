# Virtualization exercise notes

These notes explain what we did in the Vagrant and Docker exercises on an M4 Mac.
No Java or Jupyter notebook is needed for either exercise.

**Reference:** [Chapter 3 lecture slides](../lecture/03_virtualization.pdf).
The page numbers below refer to PDF pages. The original exercise instructions
remain in [1-vagrant/Readme.md](1-vagrant/Readme.md) and [2-docker/README.md](2-docker/README.md).

## 1. Why virtualization?

The lecture explains that cloud systems need to share resources, isolate workloads,
and separate software from particular physical machines (pages 2–5).
We explored two ways to do this:

| Vagrant and VirtualBox | Docker |
| --- | --- |
| Runs a complete Ubuntu virtual machine | Runs isolated application processes in containers |
| The VM has its own Linux kernel | Containers share a Linux kernel |
| Vagrant automates VM configuration | A Dockerfile automates image construction |
| Our web stack runs together inside Ubuntu | Each Docker exercise server runs in its own container |

**Mac detail:** Docker Desktop runs these Linux containers inside a Linux VM.
They share that VM's Linux kernel, not the macOS kernel. This adds context to the
lecture's container diagrams on pages 29–30 and 35.

## 2. Vagrant: what we built

**Lecture reference: pages 11–12 and 19–23.**

We created an Ubuntu 24.04 ARM64 VM using VirtualBox. Your Mac is the **host**;
Ubuntu is the **guest**. VirtualBox provides the virtual hardware, while Vagrant
reads the configuration and tells VirtualBox what to create.

The setup is in `1-vagrant/vagrant/`:

| File | Purpose |
| --- | --- |
| `Vagrantfile` | Defines the Ubuntu box, ARM64 architecture, 1024 MB RAM, forwarding, and setup commands |
| `default` | NGINX configuration, including where PHP requests go |
| `index.html` | The exercise webpage |
| `info.php` | A test that displays PHP information |

A Vagrant **box** is the reusable template. The VM created from it has its own
changing disk contents, such as installed packages and database data.

### What provisioning installed

The shell provisioner runs **inside Ubuntu**, as root. It:

1. Updates the package index.
2. Installs NGINX, MySQL server/client, PHP-FPM, PHP CLI, and PHP's MySQL extension.
3. Starts the services and enables them on later boots.
4. Sets the local MySQL root password to `secret` for this exercise.
5. Copies the source web files and NGINX configuration into their installed locations.
6. Checks NGINX configuration and reloads the server.

The shared folder `/vagrant` inside Ubuntu points to the Mac folder containing
our Vagrantfile. However, NGINX serves **copies** placed in `/usr/share/nginx/www`.
After editing a source page on the Mac, rerun provisioning to update that copy.

### Where to run commands

From `03-virtualization`, in your **Mac terminal**:

```bash
cd exercise/1-vagrant/vagrant
vagrant up --provider=virtualbox
```

The first startup creates and provisions the VM. For an existing VM, use this
when you want to rerun setup explicitly:

```bash
vagrant provision
```

To enter Ubuntu:

```bash
vagrant ssh
```

Now `apt-get`, `systemctl`, and `mysql` run in Ubuntu. They do not need Mac
replacements. Type `exit` to return to your Mac; leaving SSH does not stop the VM.

### Follow a browser request

Open **http://localhost:8081/** on your Mac:

```text
Mac browser → Mac port 8081 → Ubuntu port 80 → NGINX → index.html
```

For **http://localhost:8081/info.php**, NGINX sends the request to PHP-FPM through
`/run/php/php8.3-fpm.sock`, and PHP executes the script.
The Mac's localhost and Ubuntu's localhost are different environments; port
forwarding connects the browser to the guest service.

### Check MySQL

Inside Ubuntu after `vagrant ssh`:

```bash
mysql -u root -p
```

Enter `secret` when prompted. The password characters are not displayed.
At the `mysql>` prompt:

```sql
SELECT VERSION();
SELECT 1;
exit
```

Type `exit` again to return from Ubuntu to your Mac.
The password is configured using SQL with `caching_sha2_password`, replacing the
handout's older password-preconfiguration commands. After setup, passwordless
`sudo mysql` is not the expected login method.

### What we adjusted for this Mac and Ubuntu version

- **ARM64:** matches the M4 chip; the downloaded Ubuntu box booted successfully.
- **Ubuntu 24.04:** used consistently despite one mention of 22.04 in the handout.
- **Port 8081:** replaces 8080 in our browser URLs; Ubuntu still uses port 80.
- **Socket-check workaround:** the Ruby block at the top of the Vagrantfile fixes
  the false port collisions observed with this macOS/Vagrant combination.
- **MySQL:** the root password is set explicitly with SQL. A temporary client
  configuration allows repeat provisioning, and is removed when the script exits.
- **PHP:** installing PHP-FPM and PHP CLI explicitly avoids pulling in Apache,
  which would compete with NGINX for port 80.

The red installer output did not automatically mean failure. Vagrant colors
stderr red, and programs also use that stream for informational messages.

### Stop and restart

On your **Mac**, in the Vagrant folder:

```bash
vagrant halt
vagrant up
```

`halt` shuts down the guest and stops the website while preserving its disk.
`destroy` would delete the VM and its database data. Use `vagrant reload --provision`
after changing VM settings such as memory or forwarded ports.

## 3. Docker Part 1: configure a container manually

**Lecture reference: pages 27–30, 35–36, and 45.**

With Docker Desktop running, we started Alpine from the **Mac terminal**:

```bash
docker run -it alpine sh
```

`run` creates a new container. `-it` gives us an interactive terminal, and `sh`
is its main process. The `/ #` prompt means we are inside Alpine.

Inside that container, we ran:

```bash
whoami
apk update
apk add nginx curl
nginx
curl localhost
```

`whoami` printed `root`; `apk` installed packages in this container's writable
filesystem. Root is powerful inside the container, but is not automatically
root on macOS. Namespaces provide separate views of processes, networking, and
filesystems; cgroups account for and can limit resource use (pages 27–28).

### Why curl disappeared

We exited and ran `docker run -it alpine sh` again. That created a **second**
container from the unchanged Alpine image, so it did not have the packages installed
in the first one. The first container's files were still there.

From the Mac, we found it and returned to it:

```bash
docker ps -a
docker start -ai serene_euler
```

We restarted NGINX inside it. Installed files survive a container stop, but running
processes do not. Since the shell was the main process, exiting it stopped this
container. `docker ps` shows running containers; `docker ps -a` also shows stopped ones.

### Why the server returned 404

NGINX responded, but the Alpine package's default site deliberately returned 404.
This meant the server was reachable, not that the expected webpage existed.
We supplied `2-docker/lab/nginx.conf` and `2-docker/lab/index.html` to serve a page.
This was a package configuration difference, not an M4 problem.

## 4. Docker bonus: save the manual work as an image

**Lecture reference: pages 36 and 45.**

An **image** packages files and startup defaults. A **container** is an instance
created from an image, with its own state. Stopping a container is different from
removing it, and changing a container does not change its original image.

We saved the configured container as a new local image:

```bash
docker commit serene_euler cloudcomputing/nginx:manual
```

A commit saves filesystem changes and configuration, not live processes or the
contents of mounted volumes.

The following creation command was already run on your Mac:

```bash
docker run -d --name virtualization-manual --label course=virtualization \
  -p 127.0.0.1:8082:80 \
  cloudcomputing/nginx:manual nginx -g 'daemon off;'
```

- `-d` detaches the container from the terminal.
- `127.0.0.1:8082:80` publishes container port 80 on your Mac's local port 8082.
- `daemon off;` keeps NGINX in the foreground as the main process.

Open **http://localhost:8082/**. To restart the existing container, use
`docker start virtualization-manual`; do not repeat `docker run` with the same name.
The original Part 1 container had no published ports, so its web server was not
available through your Mac's localhost.

## 5. Docker Part 2: automate the image build

**Lecture reference: pages 42–45.**

The files needed to build our image are in `2-docker/lab/`.
A Dockerfile records the construction steps so the setup can be rebuilt:

| Instruction | Meaning in our Dockerfile |
| --- | --- |
| `FROM alpine:3.11` | Start from the Alpine version requested by the handout |
| `RUN` | Install packages and create directories during the build |
| `COPY` | Include our NGINX configuration and HTML page |
| `EXPOSE 80` | Document the intended container port; it does not publish a Mac port |
| `ENTRYPOINT ["nginx"]` | Choose the process started by the container |
| `CMD ["-g", "daemon off;"]` | Give that process its default arguments |

The difference between **build time** and **run time** matters: packages are
installed while building; NGINX starts when a container is created or restarted.

From `03-virtualization/exercise/2-docker` on the **Mac**:

```bash
docker build -t cloudcomputing/nginx:dockerfile lab
```

`lab` is the build context directory, containing the Dockerfile and files to copy.
We then created the container:

```bash
docker run -d --name virtualization-dockerfile --label course=virtualization \
  -p 127.0.0.1:8083:80 cloudcomputing/nginx:dockerfile
```

Open **http://localhost:8083/**. This container already exists, so use
`docker start virtualization-dockerfile` to restart it.

Rebuilding an image does not update an existing container. To use changed image
contents, create a new container from the rebuilt image.
Alpine 3.11 built successfully for ARM64, but it is old; we retained it to match
the exercise. The manually configured container used Alpine 3.24.3, so the two
images are not identical environments.

## 6. Docker Part 3: serve files from the Mac

**Lecture reference: pages 36 and 45.**

We used the official NGINX image and exposed the existing `content` folder inside
its web directory. From `03-virtualization/exercise/2-docker`, the creation command was:

```bash
docker run -d --name virtualization-content --label course=virtualization \
  -p 127.0.0.1:8084:80 \
  --mount "type=bind,source=$(pwd)/content,target=/usr/share/nginx/html,readonly" \
  nginx:mainline
```

Quoting the mount argument handles spaces in your Mac's path.
Open **http://localhost:8084/** to see the QAware page and logo.
This container also already exists: restart it using `docker start virtualization-content`.

A **bind mount** exposes a specific host folder to the container. It is different
from a Docker-managed named volume. The container can read this mount but cannot
write through it. You can edit the host HTML and refresh the browser without
rebuilding the image. The external Bootstrap stylesheet requires internet access.

Compare this with Vagrant: our Vagrant provisioner copies files into a serving
folder, while this Docker container serves the mounted source folder directly.

## 7. Useful Docker commands

Run these on your **Mac**, outside the containers:

```bash
docker ps -a
docker inspect virtualization-dockerfile
docker logs --tail 10 virtualization-dockerfile
docker top virtualization-dockerfile
```

`inspect` shows configuration; `logs` reads stdout/stderr; `top` shows processes.
Our custom NGINX configuration sends logs to stdout/stderr so Docker can show them.

Stop only the three exercise servers:

```bash
docker stop virtualization-manual virtualization-dockerfile virtualization-content
```

Start them again:

```bash
docker start virtualization-manual virtualization-dockerfile virtualization-content
```

This preserves the containers and does not affect unrelated ones, such as
`open-webui-app`. Broad cleanup with `docker system prune` can remove stopped
containers you still want to keep.

## 8. What we verified

On 26 October 2026:

- Vagrant: valid Ruby syntax, valid NGINX configuration, all three services active,
  working HTML/PHP pages, MySQL password login, and successful repeat provisioning.
- Docker: manual image committed, Dockerfile image built, and all three final
  images confirmed as Linux ARM64.
- All three Docker pages returned HTTP 200 with the expected content.
- The mounted logo matched the host file, and a temporary host file was served
  immediately without rebuilding. That temporary file was removed afterward.
- The bind mount was confirmed read-only, and HTTP requests appeared in Docker logs.

The Vagrant VM was not rebuilt from scratch. The optional external Killercoda
practice was not completed. We did not benchmark VM/container performance.
The password `secret` and PHP information page are for this local exercise.

## 9. Read the lecture with these distinctions in mind

- Pages 12–13: type 1/type 2 describe hypervisor placement; paravirtualization
  describes guest cooperation. They are not interchangeable classifications.
- Pages 29–30: containers share a kernel; on this Mac, Docker Desktop supplies a Linux VM.
- Page 44: `EXPOSE` does not publish a host port. Dockerfile `VOLUME` does not choose
  a particular Mac folder; the runtime mount argument does that.
- Page 46: `docker logs` does not automatically read arbitrary system log files.
- Page 16: the JVM is an example of application virtualization. Java was not needed
  to complete these VM/container exercises.

## 10. Questions to test understanding

1. What is the difference between the Mac host, the Ubuntu guest, and a container?
2. Why did a second `docker run` not include the curl installed earlier?
3. Why does exiting SSH leave the Vagrant website running, while exiting the
   Part 1 container shell stopped that container?
4. Why can three NGINX containers all listen on port 80?
5. Which changes require provisioning, rebuilding an image, or simply refreshing the browser?

Further references: [Vagrant CLI](https://developer.hashicorp.com/vagrant/docs/cli),
[Dockerfile reference](https://docs.docker.com/reference/dockerfile/),
[bind mounts](https://docs.docker.com/engine/storage/bind-mounts/), and the
[macOS/Vagrant port-check issue](https://github.com/hashicorp/vagrant/issues/13845).

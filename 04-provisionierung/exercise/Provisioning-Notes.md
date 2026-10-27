# Provisioning exercise notes

These notes explain the Docker, Ansible, and Packer labs we built on the M4 Mac.
Run the commands in the **Mac terminal**, unless a section explicitly says otherwise.
Docker Desktop must be running. No Java, Jupyter, or Ansible installation on macOS
is needed: Ansible runs inside a container.

**Reference:** [Chapter 4 lecture slides](../lecture/04%20Provisioning.pdf).
Page references below mean PDF pages. The original requirements are in
[README.md](README.md). Our implementations are separate from the supplied solutions.

## 1. What is provisioning?

**Lecture reference: pages 8–14.**

Provisioning automatically moves a system from its current state to a desired
state. Here the desired state is a working web server serving our HTML page.
Infrastructure as Code records the setup in files that can be reviewed, versioned,
and executed again, instead of relying on remembered manual changes.

We used three approaches:

| Tool | Input | What it does in this lab |
| --- | --- | --- |
| Docker | Dockerfile and HTML | Builds a custom Nginx image |
| Docker Compose | `compose.yaml` | Creates containers, networks, mounts, and port mappings |
| Ansible | Inventory and YAML playbook | Connects over SSH and configures running Ubuntu containers |
| Packer | HCL template and HTML | Uses a temporary container to create and tag a reusable Nginx image |

The lecture calls a repeatable action **idempotent** when applying it again leaves
the same result (page 12). For example, copying an already identical file should
not report a change. Updating to `state: latest` can still change packages later
when repositories publish newer versions.

Pages 13–14 describe **immutable infrastructure**: build a replacement image and
replace the deployed instance when its configuration changes. Our Docker and
Packer workflows demonstrate image construction; Ansible demonstrates changing
existing running targets. We do not implement a production replacement pipeline.

## 2. Our folders and names

From the repository root, start with:

```bash
cd 04-provisionierung/exercise
```

| Folder | Files and purpose |
| --- | --- |
| `1-docker/` | Dockerfile, HTML page, and Compose configuration for Nginx |
| `2-ansible/` | Managed-node Dockerfile, Compose configuration, inventory, playbook, and HTML |
| `3-packer/` | `nginx.pkr.hcl` and HTML for the Packer-built image |

Compose project names are explicitly set to `provisioning-docker` and
`provisioning-ansible`. They do not depend on the folder name. This matters because
the inventory uses names such as `provisioning-ansible-managed-node-1`.
We did not set `container_name` on the managed service: Compose needs to create
multiple independently named replicas when scaling it.

Final servers:

| Server | Container name | Browser address |
| --- | --- | --- |
| Docker Compose Nginx | `provisioning-docker-cc-nginx-1` | http://localhost:8090/ |
| Packer Nginx | `provisioning-packer-nginx` | http://localhost:8091/ |
| Apache nodes | `provisioning-ansible-managed-node-1` through `-3` | Separate automatically assigned Mac ports; see below |

Ports 8090 and 8091 avoid the earlier virtualization labs on 8082–8084. Published
ports bind to `127.0.0.1`, making these lab pages accessible from this Mac.

## 3. Exercise 1: build and run Nginx

**Lecture reference: pages 16–24.**

We first ran the stock `nginx:1.29-alpine` image and checked its default welcome
page. Then we built `cc-nginx:v1`, tested it directly, removed the temporary test
containers, and started the final server with Compose. Both temporary containers
used port 8090 in turn; they were removed before the next server started.

The Dockerfile explains how to build the image:

| Instruction | Meaning here |
| --- | --- |
| `FROM nginx:1.29-alpine` | Start with an image containing Nginx on Alpine Linux |
| `COPY` | Put our HTML into `/usr/share/nginx/html/index.html` at build time |
| `EXPOSE 80` | Document the container's HTTP port |
| `CMD ["nginx", "-g", "daemon off;"]` | Keep Nginx in the foreground when the container starts |

From `exercise/1-docker`:

```bash
docker build -t cc-nginx:v1 .
docker compose up --build -d
docker compose ps
curl http://localhost:8090/
docker compose logs --tail 10 cc-nginx
```

The build context `.` is the folder Docker can read when resolving `COPY`.
Compose's `image: cc-nginx:v1` gives the built image the requested name and tag.
`-d` starts containers in the background; Nginx still runs in the foreground
**inside** the container.

Follow a request:

```text
Mac browser -> Mac localhost:8090 -> container port 80 -> Nginx -> index.html
```

`EXPOSE` alone does not create that Mac port mapping. The `ports` setting does.
Editing the source HTML requires `docker compose up --build -d` to rebuild the
image and replace the container. This lab copies the HTML rather than serving
a live bind mount of that file.

To inspect the running container interactively:

```bash
docker compose exec cc-nginx /bin/sh
```

Type `exit` to leave the shell. Nginx continues running because this shell was
started using `exec`, rather than being the container's main process.

## 4. Exercise 2: provision Apache with Ansible

**Lecture reference: pages 27–38.**

The **control node** executes Ansible. The three **managed nodes** receive its
instructions over SSH. Docker creates these machines for the lab; Ansible then
installs and configures Apache inside them.

```text
Mac terminal
  -> docker compose exec ansible-node ...
     -> Ansible control container
        -> SSH through the cloudcomputing bridge network
           -> Ubuntu managed nodes 1, 2, and 3
```

There is no Ansible agent running on the managed nodes. They need SSH and Python,
as described on lecture pages 27–28. Our Dockerfile installs `openssh-server`,
`python3`, and `python3-apt`; Apache is deliberately left for the playbook.
Each managed container generates its own SSH host keys on its first startup.

### Start and test the lab

From `exercise/2-ansible`:

```bash
docker compose up --build -d --scale managed-node=3
docker compose exec -T ansible-node ansible --version
docker compose exec -T ansible-node ansible all -m ping
docker compose exec -T ansible-node ansible all -m command -a uptime
```

During the initial exercise we started one managed node, provisioned it with
`--limit provisioning-ansible-managed-node-1`, then scaled to three. The commands
above reproduce the final three-node setup. The inventory already lists all
three nodes. With only one running, use `--limit` to avoid trying absent nodes.

Ansible's `ping` is **not ICMP network ping**: it checks whether Ansible can log
in and execute Python on the target. `uptime` is an ad hoc remote command; its
`CHANGED` output does not mean we changed server configuration. The command
module normally reports a change unless told otherwise.

For an interactive control-node shell and SSH test:

```bash
docker compose exec ansible-node /bin/sh
ssh root@managed-node
```

Enter `verysecretpassword`. With three replicas, use
`ssh root@provisioning-ansible-managed-node-1` to select a particular node.
Type `exit` to leave SSH, then `exit` again to leave the control container.
Internal service names resolve inside the Docker network, not from the Mac terminal.

### Inventory, playbook, and tasks

**Lecture reference: pages 30–35.**

`ansible/hosts` is the inventory. It defines the `server_hosts` group, the three
target names, Python path, and SSH login variables. Compose mounts it read-only
at `/etc/ansible/hosts` in the controller.

`playbooks/install-apache.yml` describes the desired server state:

1. `ansible.builtin.ping` verifies SSH and Python connectivity.
2. `ansible.builtin.apt` installs the latest available Apache package.
3. `ansible.builtin.copy` installs our HTML with explicit ownership and permissions.
4. `ansible.builtin.service` ensures Apache is running.

A **module** implements an operation; a **task** invokes a module with arguments;
a **playbook** groups tasks and selects their hosts. Roles are useful for larger
projects but are not necessary for this small exercise.

Run the playbook, then run the same command again to check idempotency:

```bash
docker compose exec -T ansible-node ansible-playbook /work/playbooks/install-apache.yml
```

The second run should report `changed=0` for each correctly configured node,
provided no new package update or other configuration change intervenes.
We cache the apt package index for one hour to avoid refreshing it on every run.

### Open all three Apache pages

```bash
docker compose ps
docker compose port --index 1 managed-node 80
docker compose port --index 2 managed-node 80
docker compose port --index 3 managed-node 80
```

Each `port` command prints a different `127.0.0.1:PORT`. Open
`http://localhost:PORT/` using the printed number. All three containers listen on
their own port 80; Docker maps them to distinct Mac ports. Those Mac ports can
change if the containers are removed and recreated.

### What we corrected for this setup

- Ubuntu 24.04 LTS replaces the handout's Ubuntu 25.10, which reached end of life
  in July 2026. This also supplies Python 3.12 for our Ansible targets.
- Python is installed explicitly; installing SSH alone is insufficient.
- The controller runs as user `ansible`, so its playbooks are mounted under
  `/work/playbooks`, rather than the inaccessible `/root/playbooks` in the handout.
- An SSH health check and `condition: service_healthy` wait for the targets.
  Plain `depends_on` controls startup order without proving SSH is ready.
- The controller stays running with `sleep infinity`, allowing repeated `exec`
  commands. Its 100 MiB memory limit is retained, with one Ansible worker at a
  time (`ANSIBLE_FORKS=1`). Scaling still provisions every host, sequentially.
- The obsolete top-level Compose `version` field is omitted.
- Inventory and playbooks are mounted read-only. The exercise password and
  disabled SSH host verification are local lab settings; SSH ports are not
  published on the Mac.

The managed container's main process is SSH, not systemd. The playbook starts
Apache through the service module. After stopping and restarting managed nodes,
rerun the playbook to start Apache again. Installed packages remain in existing
containers, but removing those containers removes their installed state.

## 5. Exercise 3: build an image with Packer

**Lecture reference: pages 41–43.**

Packer automates image construction. Its **builder** starts a temporary Nginx
container, its file **provisioner** copies our HTML, and its **post-processor**
tags the resulting image `packer-nginx:1.0`. The image is the build **artifact**.
The temporary build container is removed when the build finishes.

We used HCL (`nginx.pkr.hcl`), matching the lecture example on page 43, instead of
the exercise's older JSON format. The base image and requested final tag remain
`nginx:1.29-alpine` and `packer-nginx:1.0`. The `run_command` explicitly uses
`/bin/sh`, because Alpine does not provide Bash by default.

For this run, Packer 1.16.2 for macOS ARM64 was downloaded into
`/private/tmp/provisioning-packer/bin/` and checked against HashiCorp's published
SHA256 checksum. Its Docker plugin is in the same temporary lab tools directory.
No system-wide Packer installation was made.

From `exercise/3-packer`, the commands used were:

```bash
export PACKER_PLUGIN_PATH=/private/tmp/provisioning-packer/plugins
/private/tmp/provisioning-packer/bin/packer init .
/private/tmp/provisioning-packer/bin/packer validate .
/private/tmp/provisioning-packer/bin/packer build .
docker image inspect packer-nginx:1.0
```

Temporary tools can disappear after a Mac cleanup or restart. For later builds,
install Packer using HashiCorp's instructions, run `unset PACKER_PLUGIN_PATH`,
and use `packer init .`, `packer validate .`, and `packer build .` normally.
Existing built images and containers do not require the Packer executable to run.

We created the final server once with:

```bash
docker run -d --name provisioning-packer-nginx --label course=provisioning \
  -p 127.0.0.1:8091:80 packer-nginx:1.0
```

Open http://localhost:8091/. That container already exists now: use
`docker start provisioning-packer-nginx` to restart it. After rebuilding the
image, replace the old container to use the new image contents.

## 6. Stop, restart, and remove only this lab

From `exercise/1-docker`:

```bash
docker compose stop
docker compose up -d
```

From `exercise/2-ansible`:

```bash
docker compose stop
docker compose up -d --scale managed-node=3
docker compose exec -T ansible-node ansible-playbook /work/playbooks/install-apache.yml
```

For Packer's final server, from any Mac terminal:

```bash
docker stop provisioning-packer-nginx
docker start provisioning-packer-nginx
```

`stop` preserves existing container files. To remove a Compose lab, run
`docker compose down` from its own folder. To remove Packer's final container,
run `docker rm -f provisioning-packer-nginx`. Removing the managed nodes means
the next `up` creates fresh Ubuntu nodes that need the playbook again.
These commands target this chapter's containers; the earlier labs remain separate.

## 7. Verification and limits

Verified on **26 October 2026** on this Mac:

- Docker's engine reported `aarch64`. The custom Nginx image, managed Ubuntu image,
  Ansible controller image, and Packer image all reported `linux/arm64`.
- The stock Nginx container returned its default welcome page. The directly
  started custom image returned our page before we replaced it with Compose.
- The final Docker Compose Nginx and Packer Nginx pages returned HTTP 200 and
  matched their source HTML byte for byte.
- Ansible reported core version **2.18.19**, with Python **3.12.15** on the control
  node. The image tag identifies the release series, not an immutable digest.
- SSH/Python `ping` returned `pong` and remote `uptime` succeeded on all three nodes.
- The initial single-node playbook completed with `ok=4 changed=3 failed=0`.
- After scaling, the existing node required no changes; each new node reported
  `ok=4 changed=3 failed=0`.
- A full repeat run reported **`ok=4 changed=0 unreachable=0 failed=0` on all three**.
- All three Apache pages returned HTTP 200 and matched the source HTML byte for byte.
- The controller retained its **104857600-byte (100 MiB)** limit and was not OOM-killed.
- Packer **1.16.2**, with Docker plugin **1.1.4**, validated and built the template
  successfully, producing `packer-nginx:1.0`.
- All six final lab containers were left running: two Nginx servers, three Apache
  targets, and one Ansible controller. Earlier virtualization containers remained running.

Apache addresses at verification time:

| Node | Address |
| --- | --- |
| 1 | http://localhost:54162/ |
| 2 | http://localhost:54276/ |
| 3 | http://localhost:54277/ |

Use `docker compose port` to rediscover these after recreating containers.
The two optional Packer bonuses (install Nginx from a plain base image and use
an Ansible provisioner inside Packer) were not implemented. We did not run the
separate AWS/Dokku example, deploy to a cloud, or push images to a registry.
Image tags and package repositories can change; this is a verified local lab,
not a dependency-locked production build.

## 8. Read the lecture with these distinctions in mind

- Pages 5–6: Linux containers share a Linux kernel. On this Mac, Docker Desktop
  supplies that kernel in a Linux VM; containers do not share the macOS kernel.
- Page 18: `docker build` takes a build context; `-f` selects a nondefault Dockerfile.
- Page 20: `EXPOSE` documents a port; `ports` or `-p` publishes it. Dockerfile
  `VOLUME` does not select a particular Mac directory; runtime mounts do that.
- Pages 22–24: Compose creates and connects the containers. Rebuilding or
  replacing a container can discard files stored only in its writable layer.
- Pages 27–28: Ansible needs no target agent, but does need a connection and
  suitable runtime prerequisites for the modules being used.
- Page 42: Packer supports HCL as well as the JSON format mentioned on this slide.

## 9. Questions to test understanding

1. Why does `EXPOSE 80` not make a page appear on `localhost:80` on the Mac?
2. What does Docker create before Ansible runs, and what does Ansible add afterward?
3. Why does the playbook need Python on the targets, even though Ansible runs elsewhere?
4. How can three Apache servers all listen on port 80?
5. Why does changing HTML require an image rebuild for Docker/Packer, but a
   playbook rerun for the Ansible lab?
6. What survives `stop`, and what is lost when a managed container is removed?

Further references: [Dockerfile reference](https://docs.docker.com/reference/dockerfile/),
[Compose services](https://docs.docker.com/reference/compose-file/services/),
[Ansible documentation](https://docs.ansible.com/ansible/latest/index.html),
[Packer installation](https://developer.hashicorp.com/packer/install),
[Packer Docker plugin](https://developer.hashicorp.com/packer/integrations/hashicorp/docker),
and [Ubuntu 25.10 end-of-life announcement](https://lists.ubuntu.com/archives/ubuntu-announce/2026-July/000325.html).

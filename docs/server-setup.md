# Настройка сервера — практическая работа № 5

Автор: Варвара Есина. Дата проверки: 26.10.2026.

## 1. Параметры виртуальной машины

VirtualBox 7.2.22; имя devops-vm-esina; Ubuntu Server 24.04.5 LTS amd64; 2048 МБ RAM; 2 CPU; динамический VDI 25 ГиБ. Файлы: E:\DevOps-Practice5\devops-vm-esina. Имя гостевой ОС: devops-vm. Размер корневого раздела около 11,21 ГиБ: он меньше максимального размера VDI.

После восстановления снимка 01-clean-install выполните команды ниже. Команды Linux вводятся в Ubuntu, команды PowerShell — на Windows. Пароли и закрытые ключи в репозиторий не добавлять.

## 2. Сетевые интерфейсы

Адаптер 1: NAT, enp0s3, 10.0.2.15/24. Адаптер 2: Host-only, enp0s8, 192.168.56.101/24. Адрес Windows: 192.168.56.1/24. Адрес Host-only получен по DHCP и может измениться: проверять `ip -br a`.

```bash
ip -br a
ip route
sudo apt update
sudo apt upgrade -y
```

## 3. Проброс портов

В VirtualBox задайте правило NAT SSH: TCP, адрес хоста 127.0.0.1, порт хоста 2222. До изменения sshd порт гостя 22; после изменения — 2222. Переход выполняйте, сохраняя открытую консоль Ubuntu. Текущее итоговое правило: 127.0.0.1:2222 -> guest:2222.

Проверка из PowerShell после настройки ключа:

```powershell
ssh -i "$env:USERPROFILE\.ssh\devops_vm" -p 2222 devops@127.0.0.1
```

## 4. Учётные записи и ключи

В гостевой консоли от student:

```bash
sudo adduser devops
sudo usermod -aG sudo devops
```

В PowerShell создайте ключ, если его ещё нет; существующий ключ не перезаписывайте:

```powershell
ssh-keygen -t ed25519 -C "devops-vm-key" -f "$env:USERPROFILE\.ssh\devops_vm"
Get-Content "$env:USERPROFILE\.ssh\devops_vm.pub" | ssh -p 2222 devops@127.0.0.1 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Добавьте в файл Windows `%USERPROFILE%\.ssh\config` (без расширения .txt):

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

`ssh devops` должен открывать сессию по ключу. В Ubuntu выполните `stat -c '%a %n' ~/.ssh ~/.ssh/authorized_keys`: ожидаются 700 и 600. В проверенной системе devops входит в sudo, UID 1002. Закрытый ключ хранится только на Windows.

## 5. SSH и локальные имена

Создайте резервную копию и конфигурацию в Ubuntu:

```bash
sudo cp -a /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf >/dev/null <<'EOF'
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
sudo cp -a /etc/ssh/sshd_config.d/50-cloud-init.conf /etc/ssh/sshd_config.d/50-cloud-init.conf.backup
sudo sed -i '/^[[:space:]]*PasswordAuthentication[[:space:]]/s/^/# /' /etc/ssh/sshd_config.d/50-cloud-init.conf
sudo sshd -t
sudo sshd -T | grep -Ei '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers) '
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd
```

Сначала исправьте NAT на гостевой порт 2222, затем откройте новую SSH-сессию. Не закрывайте консоль до успешной проверки. Итог: port 2222, permitrootlogin no, passwordauthentication no, maxauthtries 3, allowusers devops. Значение из 50-cloud-init.conf было обработано раньше 99-hardening.conf; конфликт устраняется комментированием прежней директивы.

Проверки в PowerShell:

```powershell
ssh devops
ssh -vvv devops exit 2>&1 | Select-String 'Authentications that can continue|Authenticated to'
ssh -i "$env:USERPROFILE\.ssh\devops_vm" -p 2222 root@127.0.0.1
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password -p 2222 devops@127.0.0.1
```

В последних двух случаях ожидается отказ. На сервере: `sudo journalctl -u ssh --since '10 minutes ago' --no-pager`.

На Windows от администратора добавьте в `C:\Windows\System32\drivers\etc\hosts` строку `192.168.56.101 devops.local`. Проверка: `ssh -i "$env:USERPROFILE\.ssh\devops_vm" -p 2222 devops@devops.local`.

В Ubuntu строка /etc/hosts должна содержать `127.0.1.1 devops-vm.devops.local devops-vm`; `sudo hostnamectl set-hostname devops-vm`; проверка `hostname -f`. Фактически получено devops-vm.devops.local. Запись Windows hosts проверена: 192.168.56.101 devops.local; журнал настройки подтвердил разрешение имени. Подключение с Windows по имени devops.local проверено: команда hostname -f вернула devops-vm.devops.local. При первом входе через Host-only сверьте отпечаток ключа с консолью: SHA256:8o3y/eOBlOl98ifHG5i7npD98WpToyTtppbvg93hhtc. На сервере `grep "^hosts:" /etc/nsswitch.conf` возвращает `hosts: files dns`: сначала /etc/hosts, затем DNS через системный резолвер.

## 6. Межсетевой экран и аудит

В Ubuntu:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw logging medium
sudo ufw --force enable
sudo ufw status verbose
```

Сначала разрешается SSH, затем включается UFW. Итоговая проверка подтвердила active, deny incoming, allow outgoing, LIMIT 2222/tcp и ALLOW 80/443 для IPv4 и IPv6.

Из Windows выполните `curl.exe --noproxy "*" -m 3 http://192.168.56.101:8080`. Ожидается тайм-аут. Сам тайм-аут не доказывает блокировку UFW; сопоставьте его с журналом Ubuntu: `sudo grep 'UFW BLOCK' /var/log/ufw.log | tail -5`. Найдите SRC=192.168.56.1, DST=192.168.56.101, PROTO=TCP, DPT=8080.

Получение скрипта в Ubuntu без установки Git (Python 3 входит в установленную систему):

```bash
mkdir -p ~/devops-course-2026/scripts
cd ~/devops-course-2026
python3 -c "import urllib.request; urllib.request.urlretrieve('https://raw.githubusercontent.com/ba0baber/devops-course-2026/main/scripts/audit.sh', 'scripts/audit.sh')"
bash -n scripts/audit.sh
bash scripts/audit.sh
echo $?
```

Воспроизводимый отрицательный тест из каталога проекта (не перезапускать SSH с тестовой настройкой):

```bash
sudo cp -a /etc/ssh/sshd_config.d/99-hardening.conf /etc/ssh/sshd_config.d/99-hardening.conf.audit-backup
sudo sed -i 's/^MaxAuthTries .*/MaxAuthTries 10/' /etc/ssh/sshd_config.d/99-hardening.conf
bash scripts/audit.sh; echo "negative exit=$?"
sudo cp -a /etc/ssh/sshd_config.d/99-hardening.conf.audit-backup /etc/ssh/sshd_config.d/99-hardening.conf
sudo sshd -t
bash scripts/audit.sh; echo "restored exit=$?"
```

Не прерывайте тест до восстановления конфигурации; при прерывании восстановите файл из audit-backup и выполните sshd -t.

Аудит проверяет запрет root, запрет паролей, нестандартный SSH-порт, MaxAuthTries=3, активность UFW и deny incoming. Проверено: 6 успешных проверок, код 0. При временном MaxAuthTries=10: 5 успешных, 1 ошибка, код 1. Конфигурация восстановлена до 3, повторно 6 успешных, код 0. Для отрицательного теста сервис не перезапускался; аудит читает конфигурацию через sshd -T.

## 7. Снимки и восстановление

- 01-clean-install — установленная Ubuntu, до настройки пользователя и ключей; 26.10.2026, 16:52:22 МСК.
- 02-keys-configured — пользователь devops и рабочий вход по ключу; 26.10.2026, 17:38:08 МСК.
- 03-ssh-hardened — SSH на 2222, запрет root/паролей, успешные проверки входа; 26.10.2026, 18:24:26 МСК, до UFW.

Дополнительно сохранён 00-before-boot-recovery. Нужные три снимка существуют; снимок 03 имеет UUID 488039ae-5824-46e1-80aa-b98414bbc68c. При восстановлении проверяйте правило NAT: старые снимки содержат гостевой порт 22. Откат удаляет изменения после выбранного снимка: сначала сохраните нужные файлы.

Возникшие трудности: microk8s, случайно выбранный при установке, вызывал зависания при 2 ГБ RAM; отключён через snap disable microk8s. Файл SSH config.txt переименован в config. После переключения порта исправлены NAT и ssh.socket. Итоговые ресурсы VM возвращены к 2 ГБ RAM и 2 CPU.

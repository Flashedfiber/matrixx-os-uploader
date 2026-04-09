# Matrixx-OS Nextcloud CLI Uploader

A secure, team-friendly CLI tool to upload, list, and delete Custom Rom builds on Nextcloud.

---

## 🚀 Quick Start

```bash
git clone https://github.com/Flashedfiber/automated-nextcloud-uploader.git
cd to target directory
./setup.sh
```

---

## 🔐 Setup Credentials

Edit `.env` file:

```bash
nano .env
```

Add:

```
NC_USER=your_username
NC_PASS=your_app_password
```

> 💡 Use a Nextcloud **App Password** (Settings → Security)

---

## 📤 Upload

```bash
./nc.sh upload file.zip
```

### Flow:

1. Select Android version (currently `A16`)
2. Enter device codename (e.g. `lemonadep`)
3. Choose upload type:

   * `ROM` → main folder
   * `Extras` → `/extras/` folder

---

## 📂 List Files

### List ROMs:

```bash
./nc.sh list A16 lemonadep
```

### List Extras:

```bash
./nc.sh list extras A16 lemonadep
```

---

## 🗑️ Delete Files

### Delete ROM:

```bash
./nc.sh delete A16 lemonadep file.zip
```

### Delete Extras:

```bash
./nc.sh delete extras A16 lemonadep file.zip
```

---

## 📁 Folder Structure

```
Lunaris-AOSP/
└── A16/
    └── <device>/
        ├── extras/
        └── ROM files
```

> 📌 The `extras/` folder is automatically created when a new device folder is created.

---

## 📜 Logs

All actions are logged in:

```bash
"device".log
```

### View logs:

```bash
cat "device".log
```

### Live logs:

```bash
tail -f "device".log
```

---

## ⚠️ Important Notes

* ❌ Uploads do not support resume
* 🔥 All users can delete files (shared model)
* 📜 Logs track all actions (upload, delete, list)

---

## 🔐 Security

* Uses **Nextcloud App Passwords**
* Credentials stored locally in `.env`
* `.env` is ignored by Git

---

## 👑 Matrixx-OS Team Tool

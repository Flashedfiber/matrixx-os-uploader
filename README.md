# Matrixx-OS Nextcloud CLI Uploader

A secure, team-friendly CLI tool to upload, list, and delete ROM builds on Nextcloud.

---

## 🚀 Quick Start

```bash
git clone https://github.com/your-org/matrixx-os-uploader.git
cd matrixx-os-uploader
chmod +x nc.sh
```

---

## 🔐 Setup

Create a `.env` file:

```
NC_USER=your_username
NC_PASS=your_app_password
```

---

## 📤 Upload

```bash
./nc.sh upload file.zip
```

---

## 📂 List

```bash
./nc.sh list A16 lemonadep
```

---

## 🗑️ Delete

```bash
./nc.sh delete A16 lemonadep file.zip
```

---

## 📖 Full Documentation

See: `docs/USAGE.md`

---

## 🔐 Security

* Uses Nextcloud App Passwords
* No credentials stored in repo

---

## 👑 Matrixx-OS Team Tool

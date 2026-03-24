# Matrixx-OS Uploader – Usage Guide

---

## 🔐 Authentication

Use a `.env` file:

```
NC_USER=your_username
NC_PASS=your_app_password
```

---

## 📤 Upload

```
./nc.sh upload file.zip
```

Steps:

1. Select Android version (A16)
2. Enter device name
3. Upload completes

---

## 📂 List Files

```
./nc.sh list A16 device
```

---

## 🗑️ Delete File

```
./nc.sh delete A16 device file.zip
```

---

## 📁 Structure

```
Matrixx-OS/A16/<device>/file.zip
```

---

## 📜 Logs

```
cat matrixx_upload.log
tail -f matrixx_upload.log
```

---

## ⚠️ Notes

* No resume support
* All users can delete files
* Logs track actions

---

## 👑 Matrixx-OS Internal Tool

# BÀI 4: THIẾT LẬP CUSTOM NETWORK & NAMED VOLUME BẰNG DOCKER CLI

---

## 1. Mục tiêu & Bối cảnh

Trong kiến trúc ứng dụng phân tán (Microservices hoặc n-tier Web App), việc liên kết các thành phần độc lập (như Web Backend và Database) đòi hỏi hai cơ chế cốt lõi:
1. **Giao tiếp mạng nội bộ an toàn (Custom Bridge Network):**
   - Cho phép các container trong cùng mạng nội bộ tìm kiếm và kết nối với nhau thông qua tên container / hostname (**Service Discovery / DNS Resolution**), thay vì hardcode địa chỉ IP (vốn có tính động và dễ thay đổi khi container khởi động lại).
   - Mạng mặc định `bridge` của Docker **không hỗ trợ** tự động phân giải tên miền (DNS resolution) bằng tên container, bắt buộc phải sử dụng **Custom Bridge Network**.
2. **Lưu trữ dữ liệu bền vững (Data Persistence với Named Volume):**
   - Theo mặc định, dữ liệu sinh ra trong container được ghi vào tầng `writable container layer`. Khi container bị xóa (`docker rm`), toàn bộ dữ liệu này sẽ biến mất vĩnh viễn (Stateless).
   - **Named Volume** tách biệt vòng đời lưu trữ khỏi vòng đời của container, giúp dữ liệu Database được duy trì an toàn ngay cả khi container bị xóa cứng hoặc nâng cấp phiên bản.

---

## 2. Kiến trúc cụm Container

```
+------------------------------------------------------------------------------------+
|                             Custom Network: app-net                                |
|                                (Subnet: 172.19.0.0/16)                             |
|                                                                                    |
|   +--------------------------+                     +---------------------------+   |
|   |   Backend Container      |                     |    Database Container     |   |
|   |     (app-container)      | --- ping/connect -> |       (db-server)         |   |
|   |      172.19.0.3          |   (via DNS: db-server)      172.19.0.2          |   |
|   |    Port: 8082:3000       |                     |        Port: 5432         |   |
|   +--------------------------+                     +-------------+-------------+   |
|                                                                  |                 |
+------------------------------------------------------------------|-----------------+
                                                                   | Mount
                                                     +-------------v-------------+
                                                     |    Named Volume: db-data  |
                                                     | (/var/lib/postgresql/data)|
                                                     |  -> Lưu trữ trên Host OS  |
                                                     +---------------------------+
```

---

## 3. Cấu trúc thư mục

```
BT4/
├── commands.sh         # Script tự động hóa toàn bộ quy trình thiết lập và kiểm thử
└── README.md           # Báo cáo kỹ thuật, phân tích kiến trúc và nhật ký kiểm thử
```

---

## 4. Chi tiết các bước thực hiện trong `commands.sh`

Tệp script [commands.sh](file:///C:/Users/duyho/Downloads/STUDY/1.%20EXCERCISES_RIKKEI/DevOpsFundamental/PTIT_IT209_Session10/BT4/commands.sh) thực hiện các bước tuần tự:

### Bước 1: Tạo Custom Bridge Network
```bash
docker network create --driver bridge app-net
```
- Khởi tạo mạng bridge tùy biến tên `app-net`. Docker sẽ tự động kích hoạt Embedded DNS Server (127.0.0.11) để quản lý việc ánh xạ tên container sang IP nội bộ.

### Bước 2: Tạo Named Volume
```bash
docker volume create db-data
```
- Cấp phát vùng nhớ lưu trữ độc lập trên host do Docker quản lý.

### Bước 3: Khởi chạy Database Container
```bash
docker run -d \
  --name db-server \
  --network app-net \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=appdb \
  -v db-data:/var/lib/postgresql/data \
  postgres:15-alpine
```
- Sử dụng base image nhẹ `postgres:15-alpine`.
- Gắn vào mạng `app-net` và mount volume `db-data` vào thư mục dữ liệu gốc `/var/lib/postgresql/data`.

### Bước 4: Khởi chạy Backend Container
```bash
docker run -d \
  --name app-container \
  --network app-net \
  -p 8082:3000 \
  -e DB_HOST=db-server \
  -e DB_PORT=5432 \
  -e DB_USER=postgres \
  -e DB_PASSWORD=postgres \
  -e DB_NAME=appdb \
  hw-backend:v1
```
- Container tham gia vào `app-net`, nhận biến môi trường `DB_HOST=db-server` để kết nối trực tiếp đến database thông qua hostname.

---

## 5. Nhật ký kiểm thử thực nghiệm (Verification Evidence)

### 5.1. Kiểm tra Network & Volume đã tạo
```bash
docker network ls | grep app-net
docker volume ls | grep db-data
```
**Kết quả thực tế:**
```text
a4e786796a7d   app-net                 bridge    local
local          db-data
```

### 5.2. Kiểm tra chi tiết mạng `app-net` (`docker network inspect app-net`)
```json
[
    {
        "Name": "app-net",
        "Id": "a4e786796a7dcc48094735b594dadb016534841b31977f9a1190744a569f8fec",
        "Driver": "bridge",
        "IPAM": {
            "Driver": "default",
            "Config": [
                {
                    "Subnet": "172.19.0.0/16",
                    "Gateway": "172.19.0.1"
                }
            ]
        }
    }
]
```

---

### 5.3. Kiểm thử DNS Resolution nội bộ (Ping `db-server` từ `app-container`)
Thực thi lệnh ping trực tiếp từ bên trong `app-container` tới hostname `db-server`:
```bash
docker exec app-container ping -c 2 db-server
```

**Kết quả thực tế:**
```text
PING db-server (172.19.0.2): 56 data bytes
64 bytes from 172.19.0.2: seq=0 ttl=64 time=0.136 ms
64 bytes from 172.19.0.2: seq=1 ttl=64 time=0.071 ms

--- db-server ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 0.071/0.103/0.136 ms
```
> **Đánh giá:** Embedded DNS Server của Docker trong `app-net` đã tự động phân giải hostname `db-server` thành địa chỉ IP nội bộ `172.19.0.2` một cách chính xác; độ trễ cực thấp (~0.1ms), tỉ lệ mất gói 0%.

---

### 5.4. Kiểm thử tính bền vững dữ liệu (Data Persistence Test)

#### Giai đoạn 1: Tạo bảng và chèn dữ liệu vào `db-server`
```bash
docker exec db-server psql -U postgres -d appdb -c "CREATE TABLE users (id SERIAL PRIMARY KEY, name VARCHAR(50), email VARCHAR(50));"
docker exec db-server psql -U postgres -d appdb -c "INSERT INTO users (name, email) VALUES ('Nguyen Van A', 'vana@example.com'), ('Tran Thi B', 'thib@example.com');"
```

Kiểm tra dữ liệu trước khi xóa:
```text
--- BEFORE REMOVE ---
 id |     name     |      email       
----+--------------+------------------
  1 | Nguyen Van A | vana@example.com
  2 | Tran Thi B   | thib@example.com
(2 rows)
```

#### Giai đoạn 2: Xóa cứng Database Container
```bash
docker rm -f db-server
```
Container `db-server` bị xóa bỏ hoàn toàn khỏi hệ thống, nhưng Named Volume `db-data` vẫn được giữ nguyên vẹn trên đĩa cứng của host.

#### Giai đoạn 3: Khởi chạy lại container `db-server` mới với cùng volume `db-data`
```bash
docker run -d \
  --name db-server \
  --network app-net \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=appdb \
  -v db-data:/var/lib/postgresql/data \
  postgres:15-alpine
```

#### Giai đoạn 4: Xác minh dữ liệu sau khi tái tạo
Truy vấn lại bảng `users` trên container mới:
```bash
docker exec db-server psql -U postgres -d appdb -c "SELECT * FROM users;"
```

**Kết quả thực tế:**
```text
--- AFTER RECREATE ---
 id |     name     |      email       
----+--------------+------------------
  1 | Nguyen Van A | vana@example.com
  2 | Tran Thi B   | thib@example.com
(2 rows)
```
> **Đánh giá:** Toàn bộ bảng `users` và 2 bản ghi dữ liệu đã được bảo toàn 100%. Quá trình mount Named Volume đảm bảo tính an toàn dữ liệu tuyệt đối cho hệ thống cơ sở dữ liệu.

---

## 6. Kết luận & Khuyến nghị vận hành
1. **Custom Network:** Luôn luôn sử dụng Custom Bridge Network thay vì Default Bridge cho các cụm container có giao tiếp nội bộ để tận dụng cơ chế DNS động và tăng tính bảo mật (cô lập khỏi các container khác).
2. **Named Volume:** Luôn gắn Named Volume cho các stateful service (PostgreSQL, MySQL, Redis, MongoDB) để đảm bảo dữ liệu không bị xóa mất trong quá trình bảo trì, cập nhật image hoặc khởi động lại container.

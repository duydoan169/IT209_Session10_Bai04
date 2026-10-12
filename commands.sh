#!/bin/bash
set -e

echo "=========================================================="
echo "BÀI 4: THIẾT LẬP CUSTOM NETWORK & NAMED VOLUME BẰNG CLI"
echo "=========================================================="

# 0. Dọn dẹp tài nguyên cũ nếu tồn tại
echo "[Step 0] Dọn dẹp container, network và volume cũ..."
docker rm -f app-container db-server 2>/dev/null || true
docker network rm app-net 2>/dev/null || true
docker volume rm db-data 2>/dev/null || true

# 1. Tạo Custom Bridge Network tên app-net
echo "[Step 1] Tạo Custom Bridge Network: app-net..."
docker network create --driver bridge app-net

# 2. Tạo Named Volume tên db-data
echo "[Step 2] Tạo Named Volume: db-data..."
docker volume create db-data

# 3. Khởi chạy Database Container (PostgreSQL 15 Alpine)
echo "[Step 3] Khởi chạy Database Container: db-server..."
docker run -d \
  --name db-server \
  --network app-net \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=appdb \
  -v db-data:/var/lib/postgresql/data \
  postgres:15-alpine

# 4. Khởi chạy Backend Web API Container tham gia app-net
echo "[Step 4] Khởi chạy Backend Container: app-container..."
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

# Chờ Database khởi động hoàn tất
echo "Đang đợi PostgreSQL khởi động sẵn sàng (5 giây)..."
sleep 5

# 5. Kiểm tra DNS Resolution qua Custom Bridge Network (Ping db-server từ app-container)
echo "[Step 5] Kiểm tra DNS Resolution từ app-container tới db-server..."
docker exec app-container ping -c 2 db-server

# 6. Kiểm tra mạng và volume
echo "[Step 6] Liệt kê Network & Volume..."
docker network ls | grep app-net
docker volume ls | grep db-data
docker network inspect app-net

# 7. Thực hiện kiểm thử tính bền vững dữ liệu (Data Persistence)
echo "=========================================================="
echo "[Step 7] KIỂM THỬ DATA PERSISTENCE VỚI NAMED VOLUME"
echo "=========================================================="

# 7.1 Thêm dữ liệu mẫu vào PostgreSQL
echo "-> Tạo bảng và chèn dữ liệu mẫu vào db-server..."
docker exec db-server psql -U postgres -d appdb -c "CREATE TABLE users (id SERIAL PRIMARY KEY, name VARCHAR(50), email VARCHAR(50));"
docker exec db-server psql -U postgres -d appdb -c "INSERT INTO users (name, email) VALUES ('Nguyen Van A', 'vana@example.com'), ('Tran Thi B', 'thib@example.com');"
echo "-> Dữ liệu hiện tại trong db-server:"
docker exec db-server psql -U postgres -d appdb -c "SELECT * FROM users;"

# 7.2 Xóa cứng container Database
echo "-> XÓA CỨNG CONTAINER DB (docker rm -f db-server)..."
docker rm -f db-server

# 7.3 Khởi chạy lại container Database mới gắn cùng Volume db-data
echo "-> Khởi chạy container db-server MỚI gắn cùng volume db-data..."
docker run -d \
  --name db-server \
  --network app-net \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=appdb \
  -v db-data:/var/lib/postgresql/data \
  postgres:15-alpine

echo "Đang đợi container db-server mới sẵn sàng (5 giây)..."
sleep 5

# 7.4 Xác minh dữ liệu không bị mất sau khi tái tạo container
echo "-> XÁC MINH DỮ LIỆU SAU KHI TÁI TẠO CONTAINER:"
docker exec db-server psql -U postgres -d appdb -c "SELECT * FROM users;"

echo "=========================================================="
echo "HOÀN TẤT KIỂM THỬ: DỮ LIỆU ĐƯỢC BẢO TOÀN THÀNH CÔNG!"
echo "=========================================================="

#!/bin/sh
# Liệt kê nội dung một thư mục cho "stack" ở dock (như macOS): mới nhất trước.
# Dùng:  dock-stack.sh <thư mục> [số mục tối đa]
# Ra:    dòng đầu "total<TAB>N" (tổng số mục), rồi mỗi dòng "mime<TAB>đường dẫn".
# Sắp theo ctime (gần với "ngày thêm vào" của macOS: file vừa tải hoặc vừa chuyển vào thư mục).
dir="$1"
n="${2:-12}"
[ -d "$dir" ] || { printf 'total\t-1\n'; exit 0; }

list=$(find "$dir" -mindepth 1 -maxdepth 1 ! -name '.*' -printf '%C@\t%p\n' 2>/dev/null | sort -rn)
total=$(printf '%s' "$list" | grep -c '')
printf 'total\t%s\n' "$total"
[ "$total" -gt 0 ] || exit 0

printf '%s\n' "$list" | head -n "$n" | cut -f2- | while IFS= read -r p; do
    m=$(file --mime-type -b -L -- "$p" 2>/dev/null)
    printf '%s\t%s\n' "${m:-application/octet-stream}" "$p"
done

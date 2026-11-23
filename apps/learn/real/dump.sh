#!/bin/bash
# In trạng thái hệ file (thư mục/file/symlink + nội dung file nhỏ) và lịch sử lệnh để backend chấm bài.
find / -xdev \( -path /proc -o -path /sys -o -path /dev -o -path /usr -o -path '/lib*' -o -path /bin -o -path /sbin \
  -o -path /var/lib -o -path /var/cache -o -path /etc/ssl -o -path /etc/alternatives -o -path /opt/ql \
  -o -path /etc/ca-certificates -o -path /etc/apparmor.d -o -path /var/tmp/.ql\* -o -path /boot -o -path /run \) -prune \
  -o -printf '%y\t%m\t%u\t%g\t%p\t%l\n' 2>/dev/null | while IFS=$'\t' read -r t m u g p l; do
  b=
  if [ "$t" = f ] && [ "$(stat -c %s "$p" 2>/dev/null || echo 0)" -le 65536 ]; then b=$(base64 -w0 "$p" 2>/dev/null); fi
  printf 'N\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$t" "$m" "$u" "$g" "$p" "$l" "$b"
done
while IFS=$'\t' read -r rc c; do printf 'H\t%s\t%s\n' "$rc" "$c"; done < <(cat /var/tmp/.qlhist 2>/dev/null)
# unit file có sẵn của gói (không nằm trong phần find ở trên vì /usr bị bỏ qua)
for u in cron nginx ssh; do f=/usr/lib/systemd/system/$u.service; [ -f "$f" ] && printf 'F\t/lib/systemd/system/%s.service\t%s\n' "$u" "$(base64 -w0 "$f")"; done
/opt/ql/dump_state.py

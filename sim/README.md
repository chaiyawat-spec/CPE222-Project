# ทดสอบ 8 ทิศโดยไม่มีบอร์ด

ติดตั้ง Icarus Verilog ให้เรียก `iverilog` และ `vvp` ได้ พร้อม Python และ Pillow (`python -m pip install pillow`) จากนั้นรันจากโฟลเดอร์ repo:

```powershell
python sim/run.py
```

หรือระบุ executable โดยตรง:

```powershell
python sim/run.py --iverilog C:/iverilog/bin/iverilog.exe --vvp C:/iverilog/bin/vvp.exe
```

สคริปต์อ่านรายการซอร์สจาก `spore.xpr` ใช้ top_game และ sprite_renderer จริง โดยใช้โมเดล clock/ROM เฉพาะการจำลองแทน Vivado IP โมเดล ROM มี latency 1 clock ตาม `.xci` และอ่านข้อมูลจาก `.coe` เดิม โมเดล clock ส่ง clock ทดสอบผ่านตรง จึงไม่ได้จำลอง PLL การทดสอบควบคุม force สัญญาณหลังรวมปุ่ม/จอยและ frame tick เพื่อให้ทดสอบได้เร็ว ไม่ได้จำลองการกดปุ่ม debounce หรือ UART แบบ end-to-end

สิ่งที่ตรวจ:

- ปุ่มทั้ง 16 รูปแบบ รวม NE และปุ่มตรงข้ามกัน การจำทิศหลังปล่อยปุ่ม reset เมนู pause และการอัปเดตเฉพาะ frame tick
- ทิศการเคลื่อนที่ NE และการหักล้างปุ่มตรงข้าม
- พื้นที่ Spike ด้านหน้า/ด้านหลังครบ 8 ทิศ ในขนาดผู้เล่น 16..160 ทีละ 2 พิกเซล และการ clamp ใกล้ขอบโลก พื้นที่ Spike แนวเฉียงใช้ AABB ครอบสี่เหลี่ยมที่หมุน จึงครอบคลุมมุมกว้างกว่ารูปจริงเล็กน้อย
- การหมุนเทียบกับ sin/cos แบบ real ครบทุกพิกเซล 48×48 ใน 8 ทิศ ตรวจ animation sway ทั้ง idle/moving ครบ 8 เฟส รวม 294,912 กรณี พิกัดนอกภาพต้องโปร่งใส และ address ที่อ่านได้ต้องอยู่ภายในภาพเดียวกัน
- การเลือก atlas ครบ 32 ชุด (2 สาย × 16 DNA masks) และลูกศร/Spike debug ทั้ง 8 ทิศ
- สแกน RGB จริงจาก sprite_renderer ทีละพิกเซล ผ่าน pipeline ทั้งสาม stage ตรวจว่าไม่มีค่า X และสร้างภาพจาก 144 crop

ผลลัพธ์อยู่ใน `sim/output/` (ไม่รวมใน Git):

| ไฟล์ | เนื้อหา |
| --- | --- |
| `eight_directions.png` | 8 ทิศ ทั้งสองสาย แบบเริ่มต้นและแบบครบ DNA |
| `eight_directions.gif` | แอนิเมชันว่ายน้ำครบ 8 เฟส ทั้งสองสาย ครบ DNA |
| `validation.txt` | ผล assertion จากชุดทดสอบ |
| `*_compile.log`, `*_run.log` | log คอมไพล์และจำลอง |

สร้างภาพจากผลจำลองเดิมซ้ำได้ด้วย `python sim/run.py --preview-only`

รหัสทิศทางคง 0=N, 1=E, 2=S, 3=W และเพิ่ม 4=NE, 5=SE, 6=SW, 7=NW การเปลี่ยนนี้คงรูปแบบความเร่งและความเร็วแยกแกนเดิมไว้ จึงยังไม่ได้ normalize ความเร็วแนวเฉียง

ภาพเป็นผลจำลองของ RTL พร้อม ROM จริง ไม่ใช่ภาพถ่ายจากบอร์ด การจำลองไม่ยืนยันการใช้ทรัพยากร FPGA, timing closure หรือ bitstream ล่าสุด ต้องตรวจด้วย Vivado และบอร์ดต่อไป

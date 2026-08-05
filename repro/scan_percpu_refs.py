import subprocess,sys,re,os
NM=os.path.expanduser("~/rtems/7/bin/microblaze-rtems7-nm")
OD=os.path.expanduser("~/rtems/7/bin/microblaze-rtems7-objdump")
exe=sys.argv[1]
syms={}
for l in subprocess.run([NM,exe],capture_output=True,text=True).stdout.split('\n'):
    p=l.split()
    if len(p)==3: syms[p[2]]=int(p[0],16)
pc=syms.get('_Per_CPU_Information')
if pc is None: print("no percpu"); sys.exit()
d=subprocess.run([OD,'-d','--no-show-raw-insn',exe],capture_output=True,text=True).stdout
prev=None
counts={}
for l in d.split('\n'):
    m=re.match(r'^\s*([0-9a-f]+):\s+(\S+)\s+(.*)$',l)
    if not m: prev=None; continue
    op=m.group(2); args=m.group(3)
    if op=='imm':
        prev=int(args.strip())&0xffff; continue
    if prev is not None:
        mm=re.match(r'^(r\d+), r0, (-?\d+)$',args.strip())
        if mm:
            addr=(prev<<16)|(int(mm.group(2))&0xffff)
            off=addr-pc
            if 0<=off<64:
                counts[(op,off)]=counts.get((op,off),0)+1
    prev=None
print(os.path.basename(exe),"_Per_CPU_Information=0x%x"%pc)
for k in sorted(counts): print("   %-6s +%-3d  x%d"%(k[0],k[1],counts[k]))

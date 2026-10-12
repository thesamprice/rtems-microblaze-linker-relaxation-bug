	.text
	.align	2
	.ent	cshift
	.type	cshift, @function
cshift:
	.frame	r1,28,r15		# vars= 0, regs= 0, args= 24
	.mask	0x00008000
	addik	r3,r0,9	# 0x9
	cmpu	r18,r7,r3
	blti	r18,$L2
	addk	r3,r0,r7
	addk	r3,r7,r7
	addk	r3,r3,r3
	addik	r3,r3,$L4
	lwi	r3,r3,0
	bra	r3 
	.rodata
	.align	2
$L4:
	.gpword	$L14
	.gpword	$L12
	.gpword	$L11
	.gpword	$L10
	.gpword	$L9
	.gpword	$L8
	.gpword	$L7
	.gpword	$L6
	.gpword	$L5
	.gpword	$L3
	.text
$L5:
	src	r7,r5
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	andi	r7,r7,-16777216
	addk	r4,r0,r6
	srl	r4,r6
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	addk	r3,r0,r5
	sra	r3,r5
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	rtsd	r15, 8
	
	or	r4,r7,r4
$L3:
	src	r7,r5
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	andi	r7,r7,-8388608
	addk	r4,r0,r6
	srl	r4,r6
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	addk	r3,r0,r5
	sra	r3,r5
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	rtsd	r15, 8
	
	or	r4,r7,r4
$L14:
	addk	r3,r5,r0
	rtsd	r15, 8
	
	addk	r4,r6,r0
$L12:
	srl	r4,r6
	sra	r3,r5
	src	r6,r5
	src	r6,r6
	andi	r6,r6,-2147483648
	rtsd	r15, 8
	
	or	r4,r6,r4
$L11:
	src	r7,r5
	src	r7,r7
	src	r7,r7
	andi	r7,r7,-1073741824
	addk	r4,r0,r6
	srl	r4,r6
	srl	r4,r4
	addk	r3,r0,r5
	sra	r3,r5
	sra	r3,r3
	rtsd	r15, 8
	
	or	r4,r7,r4
$L10:
	src	r7,r5
	src	r7,r7
	src	r7,r7
	src	r7,r7
	andi	r7,r7,-536870912
	addk	r4,r0,r6
	srl	r4,r6
	srl	r4,r4
	srl	r4,r4
	addk	r3,r0,r5
	sra	r3,r5
	sra	r3,r3
	sra	r3,r3
	rtsd	r15, 8
	
	or	r4,r7,r4
$L9:
	src	r7,r5
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	andi	r7,r7,-268435456
	addk	r4,r0,r6
	srl	r4,r6
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	addk	r3,r0,r5
	sra	r3,r5
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	rtsd	r15, 8
	
	or	r4,r7,r4
$L8:
	src	r7,r5
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	andi	r7,r7,-134217728
	addk	r4,r0,r6
	srl	r4,r6
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	addk	r3,r0,r5
	sra	r3,r5
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	rtsd	r15, 8
	
	or	r4,r7,r4
$L7:
	src	r7,r5
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	andi	r7,r7,-67108864
	addk	r4,r0,r6
	srl	r4,r6
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	addk	r3,r0,r5
	sra	r3,r5
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	rtsd	r15, 8
	
	or	r4,r7,r4
$L6:
	src	r7,r5
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	src	r7,r7
	andi	r7,r7,-33554432
	addk	r4,r0,r6
	srl	r4,r6
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	srl	r4,r4
	addk	r3,r0,r5
	sra	r3,r5
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	sra	r3,r3
	rtsd	r15, 8
	
	or	r4,r7,r4
$L2:
	addik	r1,r1,-28
	swi	r15,r1,0
	brlid	r15,abort
	nop		# Unfilled delay slot

	.end	cshift
$Lfe1:
	.size	cshift,$Lfe1-cshift
	.rodata
	.align	2
$LC0:
	.ascii "n=\0"
	.align	2
$LC1:
	.ascii "0x\0"
	.align	2
$LC2:
	.ascii " got=\0"
	.align	2
$LC3:
	.ascii " want=\0"
	.align	2
$LC4:
	.ascii "\15\12\0"
	.align	2
$LC5:
	.ascii "OK\15\12\0"
	.align	2
$LC6:
	.ascii "BAD\15\12\0"
	.align	2
$LC7:
	.ascii "0123456789abcdef\0"
	.section	.text.startup,"ax",@progbits
	.align	2
	.globl	main
	.ent	main
	.type	main, @function
main:
	.frame	r1,76,r15		# vars= 8, regs= 10, args= 24
	.mask	0x7fc88000
	addik	r1,r1,-76
	swi	r19,r1,36
	swi	r30,r1,72
	addik	r19,r0,-2080374776
	addik	r30,r0,-2080374780
	addik	r4,r0,0x7654321f
	addik	r5,r0,0xedcba980 #li => la
	swi	r22,r1,40
	swi	r23,r1,44
	swi	r24,r1,48
	swi	r25,r1,52
	swi	r26,r1,56
	swi	r27,r1,60
	swi	r28,r1,64
	swi	r29,r1,68
	swi	r15,r1,0
	swi	r4,r1,28
	swi	r5,r1,32
	addik	r22,r0,0x00000000
	addik	r23,r0,0x00000000 #li => la
	addk	r27,r0,r0
	addik	r29,r0,110	# 0x6e
	addik	r26,r0,48	# 0x30
	addik	r28,r0,32	# 0x20
	addik	r24,r0,0x00000000
	addik	r25,r0,0x00000001 #li => la
$L77:
	lwi	r4,r1,28
	lwi	r5,r1,32
	addk	r7,r23,r0
	addk	r6,r5,r0
	brlid	r15,cshift
	
	addk	r5,r4,r0
	lwi	r8,r1,28
	lwi	r9,r1,32
	andi	r5,r23,32 #and1
	beqid	r5,$L19
	addk	r7,r8,r8
	andi	r18,r23,31
	addk	r6,r0,r8
	beqid	r18,.+20
	addk	r6,r6,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	sra	r6,r6
	addk	r7,r0,r8
	sra	r7,r8
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
	sra	r7,r7
$L20:
	xor	r5,r3,r7
	bneid	r5,$L54
	xor	r5,r4,r6
	beqi	r5,$L21
$L54:
	addk	r8,r29,r0
	addik	r9,r0,$LC0
	addik	r9,r9,1
$L23:
	lwi	r5,r19,0
	andi	r5,r5,8 #and1
	bnei	r5,$L23
	swi	r8,r30,0
	lbui	r8,r9,0
	sext8	r8,r8
	bneid	r8,$L23
	addik	r9,r9,1
	addk	r8,r26,r0
	addik	r9,r0,$LC1
	addik	r9,r9,1
$L25:
	lwi	r5,r19,0
	andi	r5,r5,8 #and1
	bnei	r5,$L25
	swi	r8,r30,0
	lbui	r8,r9,0
	sext8	r8,r8
	bneid	r8,$L25
	addik	r9,r9,1
	addik	r8,r0,60	# 0x3c
	addk	r10,r22,r22
	andi	r5,r8,32 #and1
$L79:
	beqid	r5,$L27
	xori	r5,r8,-1
	andi	r18,r8,31
	addk	r5,r0,r22
	beqid	r18,.+20
	addk	r5,r5,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	srl	r5,r5
$L28:
	addik	r5,r5,$LC7
	lbui	r9,r5,0
	sext8	r9,r9
$L29:
	lwi	r5,r19,0
	andi	r5,r5,8 #and1
	bnei	r5,$L29
	addik	r8,r8,-4
	swi	r9,r30,0
	xori	r5,r8,-4
	bneid	r5,$L79
	andi	r5,r8,32 #and1
	addk	r8,r28,r0
	addik	r9,r0,$LC2
	addik	r9,r9,1
$L31:
	lwi	r5,r19,0
	andi	r5,r5,8 #and1
	bnei	r5,$L31
	swi	r8,r30,0
	lbui	r8,r9,0
	sext8	r8,r8
	bneid	r8,$L31
	addik	r9,r9,1
	addk	r8,r26,r0
	addik	r9,r0,$LC1
	addik	r9,r9,1
$L33:
	lwi	r5,r19,0
	andi	r5,r5,8 #and1
	bnei	r5,$L33
	swi	r8,r30,0
	lbui	r8,r9,0
	sext8	r8,r8
	bneid	r8,$L33
	addik	r9,r9,1
	addik	r8,r0,60	# 0x3c
	addk	r9,r3,r3
	andi	r5,r8,32 #and1
$L80:
	beqid	r5,$L35
	xori	r5,r8,-1
	andi	r18,r8,31
	addk	r5,r0,r3
	beqid	r18,.+20
	addk	r5,r5,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	srl	r5,r5
$L36:
	andi	r5,r5,15 #and1
	addik	r5,r5,$LC7
	lbui	r10,r5,0
	sext8	r10,r10
$L37:
	lwi	r5,r19,0
	andi	r5,r5,8 #and1
	bnei	r5,$L37
	addik	r8,r8,-4
	swi	r10,r30,0
	xori	r5,r8,-4
	bneid	r5,$L80
	andi	r5,r8,32 #and1
	addk	r4,r28,r0
	addik	r5,r0,$LC3
	addik	r5,r5,1
$L39:
	lwi	r3,r19,0
	andi	r3,r3,8 #and1
	bnei	r3,$L39
	swi	r4,r30,0
	lbui	r4,r5,0
	sext8	r4,r4
	bneid	r4,$L39
	addik	r5,r5,1
	addk	r4,r26,r0
	addik	r5,r0,$LC1
	addik	r5,r5,1
$L41:
	lwi	r3,r19,0
	andi	r3,r3,8 #and1
	bnei	r3,$L41
	swi	r4,r30,0
	lbui	r4,r5,0
	sext8	r4,r4
	bneid	r4,$L41
	addik	r5,r5,1
	addik	r4,r0,60	# 0x3c
	addk	r8,r7,r7
	andi	r3,r4,32 #and1
$L81:
	beqid	r3,$L43
	xori	r3,r4,-1
	andi	r18,r4,31
	addk	r3,r0,r7
	beqid	r18,.+20
	addk	r3,r3,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	srl	r3,r3
$L44:
	andi	r3,r3,15 #and1
	addik	r3,r3,$LC7
	lbui	r5,r3,0
	sext8	r5,r5
$L45:
	lwi	r3,r19,0
	andi	r3,r3,8 #and1
	bnei	r3,$L45
	addik	r4,r4,-4
	swi	r5,r30,0
	xori	r3,r4,-4
	bneid	r3,$L81
	andi	r3,r4,32 #and1
	addik	r5,r0,$LC4
	addik	r4,r0,13	# 0xd
$L48:
	addik	r5,r5,1
$L47:
	lwi	r3,r19,0
	andi	r3,r3,8 #and1
	bnei	r3,$L47
	swi	r4,r30,0
	lbui	r4,r5,0
	sext8	r4,r4
	bnei	r4,$L48
	addik	r27,r27,1
$L21:
	add	r23,r23,r25
	addc	r22,r22,r24
	bneid	r22,$L77
	xori	r3,r23,10
	bnei	r3,$L77
	addik	r6,r0,$LC6
	bnei	r27,$L50
	addik	r6,r0,$LC5
$L50:
	lbui	r5,r6,0
	addik	r4,r0,-2080374776
	addik	r7,r0,-2080374780
	sext8	r5,r5
$L52:
	addik	r6,r6,1
$L51:
	lwi	r3,r4,0
	andi	r3,r3,8 #and1
	bnei	r3,$L51
	swi	r5,r7,0
	lbui	r5,r6,0
	sext8	r5,r5
	bnei	r5,$L52
	rsubk	r5,r27,r0
	or	r5,r5,r27
	addk	r3,r0,r5
	srl	r3,r5
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	srl	r3,r3
	brlid	r15,exit
	
	addk	r5,r3,r0
$L35:
	andi	r18,r5,31
	addk	r10,r0,r9
	beqid	r18,.+20
	addk	r10,r10,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	addk	r10,r10,r10
	andi	r18,r8,31
	addk	r5,r0,r4
	beqid	r18,.+20
	addk	r5,r5,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	srl	r5,r5
	brid	$L36
	or	r5,r10,r5
$L27:
	andi	r18,r5,31
	addk	r9,r0,r10
	beqid	r18,.+20
	addk	r9,r9,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	addk	r9,r9,r9
	andi	r18,r8,31
	addk	r5,r0,r23
	beqid	r18,.+20
	addk	r5,r5,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	srl	r5,r5
	brid	$L28
	or	r5,r9,r5
$L43:
	andi	r18,r3,31
	addk	r5,r0,r8
	beqid	r18,.+20
	addk	r5,r5,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	addk	r5,r5,r5
	andi	r18,r4,31
	addk	r3,r0,r6
	beqid	r18,.+20
	addk	r3,r3,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	srl	r3,r3
	brid	$L44
	or	r3,r5,r3
$L19:
	xori	r6,r23,-1
	andi	r18,r6,31
	addk	r5,r0,r7
	beqid	r18,.+20
	addk	r5,r5,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	addk	r5,r5,r5
	andi	r18,r23,31
	addk	r6,r0,r9
	beqid	r18,.+20
	addk	r6,r6,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	srl	r6,r6
	andi	r18,r23,31
	addk	r7,r0,r8
	beqid	r18,.+20
	addk	r7,r7,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	sra	r7,r7
	brid	$L20
	or	r6,r5,r6
	.end	main
$Lfe2:
	.size	main,$Lfe2-main

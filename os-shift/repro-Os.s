	.text
	.align	2
	.ent	puts_
	.type	puts_, @function
puts_:
	.frame	r1,0,r15		# vars= 0, regs= 0, args= 0
	.mask	0x00000000
	addik	r6,r0,-2080374776
	addik	r7,r0,-2080374780
	lbui	r3,r5,0
$L6:
	sext8	r3,r3
	bnei	r3,$L4
	rtsd	r15,8 
	nop		# Unfilled delay slot

$L4:
	addik	r5,r5,1
$L3:
	lwi	r4,r6,0
	andi	r4,r4,8 #and1
	bnei	r4,$L3
	swi	r3,r7,0
	brid	$L6
	lbui	r3,r5,0
	.end	puts_
$Lfe1:
	.size	puts_,$Lfe1-puts_
	.align	2
	.ent	cshift
	.type	cshift, @function
cshift:
	.frame	r1,28,r15		# vars= 0, regs= 0, args= 24
	.mask	0x00008000
	addk	r3,r5,r0
	addik	r5,r0,9	# 0x9
	cmpu	r18,r7,r5
	blti	r18,$L8
	addk	r5,r0,r7
	addk	r5,r7,r7
	addk	r5,r5,r5
	addik	r5,r5,$L10
	lwi	r5,r5,0
	brad	r5 
	addk	r4,r6,r0
	.rodata
	.align	2
$L10:
	.gpword	$L19
	.gpword	$L18
	.gpword	$L17
	.gpword	$L16
	.gpword	$L15
	.gpword	$L14
	.gpword	$L13
	.gpword	$L12
	.gpword	$L11
	.gpword	$L9
	.text
$L18:
	srl	r4,r6
	ori	r18,r0,31
	addk	r5,r3,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	addk	r5,r5,r5
	sra	r3,r3
	rtsd	r15, 8
	
	or	r4,r5,r4
$L17:
	ori	r18,r0,30
	addk	r5,r3,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	addk	r5,r5,r5
	addk	r6,r0,r4
	srl	r6,r4
	srl	r6,r6
	or	r4,r5,r6
	addk	r5,r0,r3
	sra	r5,r3
	sra	r5,r5
$L22:
	rtsd	r15, 8
	
	addk	r3,r5,r0
$L16:
	ori	r18,r0,29
	addk	r5,r3,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	addk	r5,r5,r5
	addk	r6,r0,r4
	srl	r6,r4
	srl	r6,r6
	srl	r6,r6
	or	r4,r5,r6
	addk	r5,r0,r3
	sra	r5,r3
	sra	r5,r5
	sra	r5,r5
	bri	$L22
$L15:
	ori	r18,r0,28
	addk	r5,r3,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	addk	r5,r5,r5
	addk	r6,r0,r4
	srl	r6,r4
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	or	r4,r5,r6
	addk	r5,r0,r3
	sra	r5,r3
	sra	r5,r5
	sra	r5,r5
	sra	r5,r5
	bri	$L22
$L14:
	ori	r18,r0,27
	addk	r5,r3,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	addk	r5,r5,r5
	addk	r6,r0,r4
	srl	r6,r4
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	or	r4,r5,r6
	addk	r5,r0,r3
	sra	r5,r3
	sra	r5,r5
	sra	r5,r5
	sra	r5,r5
	sra	r5,r5
	bri	$L22
$L13:
	ori	r18,r0,26
	addk	r5,r3,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	addk	r5,r5,r5
	addk	r6,r0,r4
	srl	r6,r4
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	or	r4,r5,r6
	brid	$L22
	ori	r18,r0,6
	addk	r5,r3,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	sra	r5,r5
$L12:
	ori	r18,r0,25
	addk	r5,r3,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	addk	r5,r5,r5
	addk	r6,r0,r4
	srl	r6,r4
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	or	r4,r5,r6
	brid	$L22
	ori	r18,r0,7
	addk	r5,r3,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	sra	r5,r5
$L11:
	ori	r18,r0,24
	addk	r5,r3,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	addk	r5,r5,r5
	addk	r6,r0,r4
	srl	r6,r4
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	or	r4,r5,r6
	brid	$L22
	ori	r18,r0,8
	addk	r5,r3,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	sra	r5,r5
$L9:
	ori	r18,r0,23
	addk	r5,r3,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	addk	r5,r5,r5
	addk	r6,r0,r4
	srl	r6,r4
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	srl	r6,r6
	or	r4,r5,r6
	brid	$L22
	ori	r18,r0,9
	addk	r5,r3,r0
	addik	r18,r18,-1
	bneid	r18,.-4
	sra	r5,r5
$L8:
	addik	r1,r1,-28
	swi	r15,r1,0
	brlid	r15,abort
	nop		# Unfilled delay slot

$L19:
	rtsd	r15, 8
	nop		# Unfilled delay slot

	.end	cshift
$Lfe2:
	.size	cshift,$Lfe2-cshift
	.rodata
	.align	2
$LC0:
	.ascii "0x\0"
	.align	2
$LC1:
	.ascii "0123456789abcdef\0"
	.text
	.align	2
	.ent	puth
	.type	puth, @function
puth:
	.frame	r1,48,r15		# vars= 0, regs= 5, args= 24
	.mask	0x03c88000
	addik	r1,r1,-48
	swi	r22,r1,32
	addk	r22,r5,r0
	addik	r5,r0,$LC0
	swi	r24,r1,40
	swi	r25,r1,44
	addik	r24,r0,-2080374780
	addik	r25,r0,-2080374776
	swi	r19,r1,28
	swi	r23,r1,36
	swi	r15,r1,0
	addk	r23,r6,r0
	brlid	r15,puts_
	
	addik	r19,r0,60	# 0x3c
	addk	r7,r19,r0
$L29:
	addk	r5,r22,r0
	brlid	r15,__lshrdi3
	
	addk	r6,r23,r0
	andi	r4,r4,15 #and1
	addik	r4,r4,$LC1
	lbui	r3,r4,0
	sext8	r3,r3
$L24:
	lwi	r4,r25,0
	andi	r4,r4,8 #and1
	bnei	r4,$L24
	addik	r19,r19,-4
	swi	r3,r24,0
	xori	r3,r19,-4
	bneid	r3,$L29
	addk	r7,r19,r0
	lwi	r15,r1,0
	lwi	r19,r1,28
	lwi	r22,r1,32
	lwi	r23,r1,36
	lwi	r24,r1,40
	lwi	r25,r1,44
	rtsd	r15,8 
	
	addik	r1,r1,48
	.end	puth
$Lfe3:
	.size	puth,$Lfe3-puth
	.rodata
	.align	2
$LC2:
	.ascii "BAD\15\12\0"
	.align	2
$LC3:
	.ascii "OK\15\12\0"
	.align	2
$LC4:
	.ascii "n=\0"
	.align	2
$LC5:
	.ascii " got=\0"
	.align	2
$LC6:
	.ascii " want=\0"
	.align	2
$LC7:
	.ascii "\15\12\0"
	.section	.text.startup,"ax",@progbits
	.align	2
	.globl	main
	.ent	main
	.type	main, @function
main:
	.frame	r1,88,r15		# vars= 16, regs= 11, args= 24
	.mask	0xffc88000
	addik	r1,r1,-88
	swi	r28,r1,72
	swi	r29,r1,76
	swi	r30,r1,80
	swi	r31,r1,84
	addik	r28,r0,$LC4
	addik	r29,r0,$LC5
	addik	r30,r0,$LC6
	addik	r31,r0,$LC7
	addik	r4,r0,0x7654321f
	addik	r5,r0,0xedcba980 #li => la
	swi	r19,r1,44
	swi	r22,r1,48
	swi	r23,r1,52
	swi	r26,r1,64
	swi	r27,r1,68
	swi	r15,r1,0
	swi	r24,r1,56
	swi	r25,r1,60
	swi	r4,r1,28
	swi	r5,r1,32
	addik	r22,r0,0x00000000
	addik	r23,r0,0x00000000 #li => la
	addk	r19,r0,r0
	addik	r26,r0,0x00000000
	addik	r27,r0,0x00000001 #li => la
$L37:
	lwi	r4,r1,28
	lwi	r5,r1,32
	addk	r7,r23,r0
	addk	r6,r5,r0
	brlid	r15,cshift
	
	addk	r5,r4,r0
	addk	r24,r4,r0
	lwi	r4,r1,28
	lwi	r5,r1,32
	addk	r7,r23,r0
	addk	r25,r3,r0
	addk	r6,r5,r0
	brlid	r15,__ashrdi3
	
	addk	r5,r4,r0
	xor	r5,r25,r3
	bneid	r5,$L39
	addk	r5,r28,r0
	xor	r5,r24,r4
	beqi	r5,$L31
	addk	r5,r28,r0
$L39:
	swi	r3,r1,36
	brlid	r15,puts_
	
	swi	r4,r1,40
	addk	r6,r23,r0
	addk	r5,r22,r0
	brlid	r15,puth
	
	addik	r19,r19,1
	brlid	r15,puts_
	
	addk	r5,r29,r0
	addk	r6,r24,r0
	brlid	r15,puth
	
	addk	r5,r25,r0
	brlid	r15,puts_
	
	addk	r5,r30,r0
	lwi	r3,r1,36
	lwi	r4,r1,40
	addk	r5,r3,r0
	brlid	r15,puth
	
	addk	r6,r4,r0
	brlid	r15,puts_
	
	addk	r5,r31,r0
$L31:
	add	r23,r23,r27
	addc	r22,r22,r26
	bneid	r22,$L37
	xori	r3,r23,10
	bnei	r3,$L37
	addik	r5,r0,$LC2
	bnei	r19,$L34
	addik	r5,r0,$LC3
$L34:
	brlid	r15,puts_
	nop		# Unfilled delay slot

	rsubk	r5,r19,r0
	or	r5,r5,r19
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
	.end	main
$Lfe4:
	.size	main,$Lfe4-main

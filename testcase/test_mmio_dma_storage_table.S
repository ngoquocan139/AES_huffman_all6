	.file	"test_mmio_dma_storage_table.c"
	.option nopic
	.attribute arch, "rv32i2p1"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.section	.text.startup,"ax",@progbits
	.align	2
	.globl	_start
	.type	_start, @function
_start:
 #APP
# 25 "../testcase/test_mmio_dma_storage_table.c" 1
	li sp, 0x00007f00
j main

# 0 "" 2
 #NO_APP
	.size	_start, .-_start
	.align	2
	.globl	main
	.type	main, @function
main:
	li	a5,256
	li	a4,320
.L3:
	sw	zero,0(a5)
	addi	a5,a5,4
	bne	a5,a4,.L3
	li	a4,384
.L4:
	sw	zero,0(a5)
	addi	a5,a5,4
	bne	a5,a4,.L4
	li	a5,826368000
	addi	a5,a5,-1754
	sw	a5,496(zero)
	lw	t1,64(zero)
	lw	a1,68(zero)
	beq	t1,zero,.L18
	lw	a5,256(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	li	a4,1
	beq	a5,a4,.L6
.L9:
	lw	a5,320(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	li	a4,1
	bne	a5,a4,.L8
	lw	a4,324(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	bne	a4,a5,.L8
.L13:
	li	a0,1
	j	.L10
.L6:
	lw	a4,260(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	bne	a4,a5,.L9
.L11:
	li	a0,0
.L10:
	lw	a6,496(zero)
	slli	a7,a0,12
	li	a5,16384
	addi	a6,a6,1
	add	a7,a7,a5
	bne	a6,zero,.L14
	li	a6,826368000
	addi	a6,a6,-1753
.L14:
	xor	a5,t1,a6
	li	a4,1128423424
	xor	a5,a5,a7
	addi	a4,a4,816
	xor	a5,a5,a4
	slli	a4,a5,13
	xor	a5,a5,a4
	srli	a4,a5,17
	xor	a5,a5,a4
	slli	a4,a5,5
	xor	a5,a5,a4
	li	a4,979136512
	addi	a4,a4,1070
	xor	a3,a5,a4
	li	a4,-1536487424
	addi	a4,a4,-617
	xor	a5,a5,a4
	slli	a4,a5,7
	srli	a5,a5,25
	or	a5,a5,a4
	li	a4,1013903360
	addi	a4,a4,882
	add	a4,a5,a4
	srli	a2,a4,15
	slli	a4,a4,17
	or	a4,a4,a2
	li	a2,1128415232
	sw	a6,496(zero)
	addi	a2,a2,816
	li	t3,1073741824
	sw	a2,40(t3)
	li	t3,1073741824
	sw	a3,44(t3)
	li	t3,1073741824
	sw	a5,48(t3)
	li	t3,1073741824
	sw	a4,52(t3)
	slli	a0,a0,6
	sw	zero,256(a0)
	li	t3,1
	sw	t3,260(a0)
	li	t6,8192
	sw	t6,264(a0)
	sw	a7,268(a0)
	sw	t1,272(a0)
	sw	zero,276(a0)
	li	t5,9
	sw	t5,280(a0)
	sw	a2,284(a0)
	sw	a3,288(a0)
	sw	a5,292(a0)
	sw	a4,296(a0)
	sw	a6,300(a0)
	sw	zero,304(a0)
	li	t4,1073741824
	li	a5,12
	sw	a5,0(t4)
	li	a5,1073741824
	sw	t6,8(a5)
	li	a5,1073741824
	sw	a7,12(a5)
	li	a5,1073741824
	sw	t1,16(a5)
	li	a5,1073741824
	sw	t5,20(a5)
	li	a4,32
	li	a5,1073741824
	li	a3,1073741824
	sw	a4,24(a5)
	addi	a3,a3,4
	lw	a5,0(a3)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	li	a2,1998848
	sw	t3,0(t4)
	li	a4,0
	addi	a2,a2,1152
.L16:
	lw	a5,0(a3)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	andi	a6,a5,4
	bne	a6,zero,.L52
	andi	a5,a5,2
	bne	a5,zero,.L53
	addi	a4,a4,1
	bne	a4,a2,.L16
.L15:
	li	a3,1073741824
	addi	a3,a3,28
	lw	a3,0(a3)
	li	a2,1073741824
	li	a3,1073741824
	addi	a3,a3,36
	addi	a2,a2,32
	lw	a3,0(a3)
	lw	a2,0(a2)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	li	a2,1998848
	addi	a2,a2,1152
	beq	a4,a2,.L18
	beq	a3,zero,.L18
	andi	a4,a3,15
	or	a5,a4,a5
	bne	a5,zero,.L18
	sw	a3,276(a0)
	sw	zero,304(a0)
	li	a5,1
	sw	a5,256(a0)
	j	.L18
.L8:
	lw	a5,256(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	beq	a5,zero,.L11
	lw	a5,320(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	beq	a5,zero,.L13
.L18:
	lw	a5,268(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	beq	a1,zero,.L32
	lw	a4,256(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	li	a5,1
	beq	a4,a5,.L20
.L23:
	lw	a4,320(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	li	a5,1
	bne	a4,a5,.L22
	lw	a4,324(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	li	a5,3
	bne	a4,a5,.L22
.L27:
	li	a4,1
	j	.L24
.L52:
	li	a5,4
	j	.L15
.L53:
	li	a5,0
	j	.L15
.L20:
	lw	a4,260(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	li	a5,3
	bne	a4,a5,.L23
.L25:
	li	a4,0
.L24:
	lw	a2,496(zero)
	slli	t1,a4,12
	li	a5,16384
	addi	a2,a2,1
	add	t1,t1,a5
	bne	a2,zero,.L28
	li	a2,826368000
	addi	a2,a2,-1753
.L28:
	xor	a5,a1,a2
	li	a3,1128427520
	xor	a5,a5,t1
	addi	a3,a3,818
	xor	a5,a5,a3
	slli	a3,a5,13
	xor	a5,a5,a3
	srli	a3,a5,17
	xor	a5,a5,a3
	slli	a3,a5,5
	xor	a5,a5,a3
	li	a3,979136512
	addi	a3,a3,1070
	xor	a0,a5,a3
	li	a3,-1536487424
	addi	a3,a3,-617
	xor	a5,a5,a3
	slli	a3,a5,7
	srli	a5,a5,25
	or	a5,a5,a3
	li	a3,1013903360
	addi	a3,a3,882
	add	a3,a5,a3
	srli	a6,a3,15
	slli	a3,a3,17
	or	a3,a3,a6
	li	a6,1128415232
	sw	a2,496(zero)
	addi	a6,a6,818
	li	a7,1073741824
	sw	a6,40(a7)
	li	a7,1073741824
	sw	a0,44(a7)
	li	a7,1073741824
	sw	a5,48(a7)
	li	a7,1073741824
	sw	a3,52(a7)
	slli	a4,a4,6
	sw	zero,256(a4)
	li	a7,3
	sw	a7,260(a4)
	li	t4,12288
	sw	t4,264(a4)
	sw	t1,268(a4)
	sw	a1,272(a4)
	sw	zero,276(a4)
	li	a7,9
	sw	a7,280(a4)
	sw	a6,284(a4)
	sw	a0,288(a4)
	sw	a5,292(a4)
	sw	a3,296(a4)
	sw	a2,300(a4)
	sw	zero,304(a4)
	li	t3,1073741824
	li	a5,12
	sw	a5,0(t3)
	li	a5,1073741824
	sw	t4,8(a5)
	li	a5,1073741824
	sw	t1,12(a5)
	li	a5,1073741824
	sw	a1,16(a5)
	li	a5,1073741824
	sw	a7,20(a5)
	li	a3,32
	li	a5,1073741824
	li	a2,1073741824
	sw	a3,24(a5)
	addi	a2,a2,4
	lw	a5,0(a2)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	li	a5,1
	li	a1,1998848
	sw	a5,0(t3)
	li	a3,0
	addi	a1,a1,1152
.L30:
	lw	a5,0(a2)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	andi	a0,a5,4
	bne	a0,zero,.L55
	andi	a5,a5,2
	bne	a5,zero,.L56
	addi	a3,a3,1
	bne	a3,a1,.L30
.L29:
	li	a2,1073741824
	addi	a2,a2,28
	lw	a2,0(a2)
	li	a1,1073741824
	li	a2,1073741824
	addi	a2,a2,36
	addi	a1,a1,32
	lw	a2,0(a2)
	lw	a1,0(a1)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	li	a1,1998848
	addi	a1,a1,1152
	beq	a3,a1,.L32
	beq	a2,zero,.L32
	andi	a3,a2,15
	or	a5,a3,a5
	bne	a5,zero,.L32
	sw	a2,276(a4)
	sw	zero,304(a4)
	li	a5,1
	sw	a5,256(a4)
	j	.L32
.L22:
	lw	a5,256(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	beq	a5,zero,.L25
	lw	a5,320(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	beq	a5,zero,.L27
.L32:
	lw	a5,332(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	lw	a4,284(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	lw	a5,348(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	bne	a4,a5,.L34
	lw	a4,288(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	lw	a5,352(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	bne	a4,a5,.L34
	lw	a4,292(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	lw	a5,356(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	bne	a4,a5,.L34
	lw	a5,296(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	lw	a5,360(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
.L34:
	lw	a5,256(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	li	a4,1
	beq	a5,a4,.L36
.L40:
	lw	a4,320(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	li	a5,1
	bne	a4,a5,.L41
	lw	a5,324(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	bne	a5,a4,.L41
.L39:
	slli	a5,a5,6
	lw	a5,260(a5)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
.L41:
	lw	a5,256(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	li	a4,1
	beq	a5,a4,.L42
.L46:
	lw	a4,320(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	li	a5,1
	bne	a4,a5,.L47
	lw	a5,324(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	bne	a5,a4,.L47
.L45:
	slli	a5,a5,6
	lw	a6,284(a5)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	lw	a0,288(a5)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	lw	a1,292(a5)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	lw	a2,296(a5)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	li	a4,1073741824
	sw	a6,40(a4)
	li	a4,1073741824
	sw	a0,44(a4)
	li	a4,1073741824
	sw	a1,48(a4)
	li	a4,1073741824
	sw	a2,52(a4)
	li	a3,1073741824
	lw	a2,268(a5)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	lw	a4,276(a5)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	lw	a5,272(a5)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	li	a5,12
	sw	a5,0(a3)
	li	a5,1073741824
	sw	a2,8(a5)
	li	a5,1073741824
	li	a2,24576
	sw	a2,12(a5)
	li	a5,1073741824
	sw	a4,16(a5)
	li	a5,1073741824
	li	a4,2
	sw	a4,20(a5)
	li	a5,1073741824
	li	a4,32
	sw	a4,24(a5)
	li	a4,1073741824
	addi	a4,a4,4
	lw	a5,0(a4)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	li	a5,1
	sw	a5,0(a3)
	li	a5,1998848
	addi	a5,a5,1152
.L49:
	lw	a3,0(a4)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	andi	a3,a3,6
	bne	a3,zero,.L48
	addi	a5,a5,-1
	bne	a5,zero,.L49
.L48:
	li	a5,1073741824
	addi	a5,a5,28
	lw	a5,0(a5)
	li	a5,1073741824
	addi	a5,a5,36
	lw	a5,0(a5)
	li	a5,1073741824
	addi	a5,a5,32
	lw	a5,0(a5)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
.L47:
	li	a5,64
.L50:
	addi	a5,a5,-1
	bne	a5,zero,.L50
	lw	a5,256(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	lw	a5,320(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	sw	zero,0(zero)
	ebreak
.L55:
	li	a5,4
	j	.L29
.L56:
	li	a5,0
	j	.L29
.L36:
	lw	a4,260(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	bne	a4,a5,.L40
	li	a5,0
	j	.L39
.L42:
	lw	a4,260(zero)
 #APP
# 83 "../testcase/secure_storage_fw.h" 1
	nop
nop

# 0 "" 2
 #NO_APP
	bne	a4,a5,.L46
	li	a5,0
	j	.L45
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"

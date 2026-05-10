//===================================================================
// File: aes_inverse_funcs.vh
// Description: AES inverse helper functions (Verilog-2001 header)
// Author (original): Nguyen Hung Quan
// Website: http://nguyenquanicd.blogspot.com/
//===================================================================

//===================================================================
// Multiplication in GF(2^8): mul by 2
//===================================================================
function [7:0] mul2;
    input [7:0] mul2_in;
    begin
        mul2 = (mul2_in[7]) ?
               ({mul2_in[6:0], 1'b0} ^ 8'b0001_1011) :
               {mul2_in[6:0], 1'b0};
    end
endfunction

//===================================================================
// Multiplication inverse selector (0e,0b,0d,09)
//===================================================================
function [7:0] mulInv;
    input [7:0] mul_in;
    input [1:0] mul_sel;

    reg [7:0] mul2_result;
    reg [7:0] mul4_result;
    reg [7:0] mul8_result;
    reg [7:0] mul0e, mul0b, mul0d, mul09;
    begin
        mul2_result = mul2(mul_in);
        mul4_result = mul2(mul2_result);
        mul8_result = mul2(mul4_result);

        mul0e = mul2_result ^ mul4_result ^ mul8_result;
        mul0b = mul2_result ^ mul8_result ^ mul_in;
        mul0d = mul4_result ^ mul8_result ^ mul_in;
        mul09 = mul8_result ^ mul_in;

	case (mul_sel)
	  2'b00: mulInv = mul0e;
	  2'b01: mulInv = mul0b;
	  2'b10: mulInv = mul0d;
	  2'b11: mulInv = mul09;
	  default: mulInv = mul0e;
	endcase

    end
endfunction

//===================================================================
// InvMixColumns (1 column = 32-bit)
//===================================================================
function [31:0] mixcolInv;
    input [31:0] mixcolInv_in;
    begin
        mixcolInv[31:24] =
            mulInv(mixcolInv_in[31:24], 2'b00) ^
            mulInv(mixcolInv_in[23:16], 2'b01) ^
            mulInv(mixcolInv_in[15:8],  2'b10) ^
            mulInv(mixcolInv_in[7:0],   2'b11);

        mixcolInv[23:16] =
            mulInv(mixcolInv_in[31:24], 2'b11) ^
            mulInv(mixcolInv_in[23:16], 2'b00) ^
            mulInv(mixcolInv_in[15:8],  2'b01) ^
            mulInv(mixcolInv_in[7:0],   2'b10);

        mixcolInv[15:8] =
            mulInv(mixcolInv_in[31:24], 2'b10) ^
            mulInv(mixcolInv_in[23:16], 2'b11) ^
            mulInv(mixcolInv_in[15:8],  2'b00) ^
            mulInv(mixcolInv_in[7:0],   2'b01);

        mixcolInv[7:0] =
            mulInv(mixcolInv_in[31:24], 2'b01) ^
            mulInv(mixcolInv_in[23:16], 2'b10) ^
            mulInv(mixcolInv_in[15:8],  2'b11) ^
            mulInv(mixcolInv_in[7:0],   2'b00);
    end
endfunction


//===================================================================
// AES-128 inverse Rcon
//===================================================================
function [31:0] aes128_rcon_inv;
    input [3:0] rkey_sel;
    begin
        case (rkey_sel)
            4'd9: aes128_rcon_inv = 32'h0100_0000;
            4'd8: aes128_rcon_inv = 32'h0200_0000;
            4'd7: aes128_rcon_inv = 32'h0400_0000;
            4'd6: aes128_rcon_inv = 32'h0800_0000;
            4'd5: aes128_rcon_inv = 32'h1000_0000;
            4'd4: aes128_rcon_inv = 32'h2000_0000;
            4'd3: aes128_rcon_inv = 32'h4000_0000;
            4'd2: aes128_rcon_inv = 32'h8000_0000;
            4'd1: aes128_rcon_inv = 32'h1b00_0000;
            4'd0: aes128_rcon_inv = 32'h3600_0000;
            default: aes128_rcon_inv = 32'h0100_0000;
        endcase
    end
endfunction

//===================================================================
// GF(2^2) multiplication
//===================================================================
function [1:0] mulGf22;
    input [1:0] a;
    input [1:0] b;
    begin
        mulGf22[1] = (a[1]&b[1]) ^ (a[0]&b[1]) ^ (a[1]&b[0]);
        mulGf22[0] = (a[1]&b[1]) ^ (a[0]&b[0]);
    end
endfunction

//===================================================================
// GF(2^4) multiplication
//===================================================================
function [3:0] mulGf24;
    input [3:0] a;
    input [3:0] b;

    reg [1:0] a_m, a_l, b_m, b_l;
    reg [1:0] a_x, b_x;
    reg [1:0] m_mm, m_xx, m_ll;
    reg [1:0] xPhi;
    begin
        a_m = a[3:2]; a_l = a[1:0];
        b_m = b[3:2]; b_l = b[1:0];

        a_x = a_m ^ a_l;
        b_x = b_m ^ b_l;

        m_mm = mulGf22(a_m, b_m);
        m_xx = mulGf22(a_x, b_x);
        m_ll = mulGf22(a_l, b_l);

        xPhi[1] = m_mm[1] ^ m_mm[0];
        xPhi[0] = m_mm[1];

        mulGf24[3:2] = m_xx ^ m_ll;
        mulGf24[1:0] = xPhi ^ m_ll;
    end
endfunction

//===================================================================
// Affine & Inverse Affine
//===================================================================
function [7:0] affine;
    input [7:0] a;
    begin
        affine[0] = a[0]^a[4]^a[5]^a[6]^a[7]^1'b1;
        affine[1] = a[0]^a[1]^a[5]^a[6]^a[7]^1'b1;
        affine[2] = a[0]^a[1]^a[2]^a[6]^a[7];
        affine[3] = a[0]^a[1]^a[2]^a[3]^a[7];
        affine[4] = a[0]^a[1]^a[2]^a[3]^a[4];
        affine[5] = a[1]^a[2]^a[3]^a[4]^a[5]^1'b1;
        affine[6] = a[2]^a[3]^a[4]^a[5]^a[6]^1'b1;
        affine[7] = a[3]^a[4]^a[5]^a[6]^a[7];
    end
endfunction

function [7:0] affineInv;
    input [7:0] a;
    begin
        affineInv[0] = a[2]^a[5]^a[7]^1'b1;
        affineInv[1] = a[0]^a[3]^a[6];
        affineInv[2] = a[1]^a[4]^a[7]^1'b1;
        affineInv[3] = a[0]^a[2]^a[5];
        affineInv[4] = a[1]^a[3]^a[6];
        affineInv[5] = a[2]^a[4]^a[7];
        affineInv[6] = a[0]^a[3]^a[5];
        affineInv[7] = a[1]^a[4]^a[6];
    end
endfunction

//===================================================================
// GF(2^8) multiplicative inverse (composite field)
//===================================================================
function [7:0] mulGf28Inv;
    input [7:0] invInput;
    reg [7:0] after_imp, imp_inv_in;
    reg [3:0] msb, lsb, square, xLamda, lsb_xor, lsb_mul, xor_b, inv_b;
    begin
        // Isomorphic mapping
        after_imp[7] = invInput[7]^invInput[5];
        after_imp[6] = invInput[7]^invInput[6]^invInput[4]^invInput[3]^invInput[2]^invInput[1];
        after_imp[5] = invInput[7]^invInput[5]^invInput[3]^invInput[2];
        after_imp[4] = invInput[7]^invInput[5]^invInput[3]^invInput[2]^invInput[1];
        after_imp[3] = invInput[7]^invInput[6]^invInput[2]^invInput[1];
        after_imp[2] = invInput[7]^invInput[4]^invInput[3]^invInput[2]^invInput[1];
        after_imp[1] = invInput[6]^invInput[4]^invInput[1];
        after_imp[0] = invInput[6]^invInput[1]^invInput[0];

        msb = after_imp[7:4];
        lsb = after_imp[3:0];

        square[3] = msb[3];
        square[2] = msb[3]^msb[2];
        square[1] = msb[2]^msb[1];
        square[0] = msb[3]^msb[1]^msb[0];

        xLamda[3] = square[2]^square[0];
        xLamda[2] = ^square;
        xLamda[1] = square[3];
        xLamda[0] = square[2];

        lsb_xor = msb ^ lsb;
        lsb_mul = mulGf24(lsb_xor, lsb);
        xor_b   = xLamda ^ lsb_mul;

        case (xor_b)
            4'h0: inv_b = 4'h0; 4'h1: inv_b = 4'h1;
            4'h2: inv_b = 4'h3; 4'h3: inv_b = 4'h2;
            4'h4: inv_b = 4'hF; 4'h5: inv_b = 4'hC;
            4'h6: inv_b = 4'h9; 4'h7: inv_b = 4'hB;
            4'h8: inv_b = 4'hA; 4'h9: inv_b = 4'h6;
            4'hA: inv_b = 4'h8; 4'hB: inv_b = 4'h7;
            4'hC: inv_b = 4'h5; 4'hD: inv_b = 4'hE;
            4'hE: inv_b = 4'hD; 4'hF: inv_b = 4'h4;
        endcase

        imp_inv_in[7:4] = mulGf24(after_imp[7:4], inv_b);
        imp_inv_in[3:0] = mulGf24(lsb_xor, inv_b);

        mulGf28Inv[7] = imp_inv_in[7]^imp_inv_in[6]^imp_inv_in[5]^imp_inv_in[1];
        mulGf28Inv[6] = imp_inv_in[6]^imp_inv_in[2];
        mulGf28Inv[5] = imp_inv_in[6]^imp_inv_in[5]^imp_inv_in[1];
        mulGf28Inv[4] = imp_inv_in[6]^imp_inv_in[5]^imp_inv_in[4]^imp_inv_in[2]^imp_inv_in[1];
        mulGf28Inv[3] = imp_inv_in[5]^imp_inv_in[4]^imp_inv_in[3]^imp_inv_in[2]^imp_inv_in[1];
        mulGf28Inv[2] = imp_inv_in[7]^imp_inv_in[4]^imp_inv_in[3]^imp_inv_in[2]^imp_inv_in[1];
        mulGf28Inv[1] = imp_inv_in[5]^imp_inv_in[4];
        mulGf28Inv[0] = imp_inv_in[6]^imp_inv_in[5]^imp_inv_in[4]^imp_inv_in[2]^imp_inv_in[0];
    end
endfunction

//===================================================================
// AES S-Box / inverse S-Box
// encrypt_en = 1 : S-Box
// encrypt_en = 0 : inverse S-Box
//===================================================================
function [7:0] aes128_sbox;
    input [7:0] sbox_in;
    input encrypt_en;
    reg [7:0] affineInvResult, mulInvResult, before_mulInv;
    begin
        affineInvResult = affineInv(sbox_in);
        before_mulInv   = encrypt_en ? sbox_in : affineInvResult;
        mulInvResult    = mulGf28Inv(before_mulInv);
        aes128_sbox     = encrypt_en ? affine(mulInvResult) : mulInvResult;
    end
endfunction

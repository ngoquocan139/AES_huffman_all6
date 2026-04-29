//===================================================================
// File: aes_encrypt_funcs.vh
// Description: AES-128 encrypt helper functions (Verilog-2001 header)
// Author (original): Nguyen Hung Quan
// Website: http://nguyenquanicd.blogspot.com/
//===================================================================

//-----------------------------------------------------------
// Function: Rcon of AES-128 used in Key Expansion
//-----------------------------------------------------------
function [31:0] aes128_rcon;
  input [3:0] rkey_sel;
  begin
    case (rkey_sel)
      4'd0:  aes128_rcon = 32'h0100_0000;
      4'd1:  aes128_rcon = 32'h0200_0000;
      4'd2:  aes128_rcon = 32'h0400_0000;
      4'd3:  aes128_rcon = 32'h0800_0000;
      4'd4:  aes128_rcon = 32'h1000_0000;
      4'd5:  aes128_rcon = 32'h2000_0000;
      4'd6:  aes128_rcon = 32'h4000_0000;
      4'd7:  aes128_rcon = 32'h8000_0000;
      4'd8:  aes128_rcon = 32'h1b00_0000;
      4'd9:  aes128_rcon = 32'h3600_0000;
      default: aes128_rcon = 32'h3600_0000;
    endcase
  end
endfunction

//===================================================================
// GF(2^8) mul2 and mul3 (for MixColumns)
//===================================================================
function [7:0] mul2;
  input [7:0] mul2_in;
  begin
    mul2 = (mul2_in[7] == 1'b1) ?
           ({mul2_in[6:0], 1'b0} ^ 8'b0001_1011) :
           {mul2_in[6:0], 1'b0};
  end
endfunction

function [7:0] mul3;
  input [7:0] mul3_in;
  begin
    mul3 = mul2(mul3_in) ^ mul3_in;
  end
endfunction

//===================================================================
// MixColumns for one column (32-bit)
//===================================================================
function [31:0] mixcol;
  input [31:0] mixcol_in;
  begin
    mixcol[31:24] = mul2(mixcol_in[31:24]) ^ mul3(mixcol_in[23:16]) ^ mixcol_in[15:8]        ^ mixcol_in[7:0];
    mixcol[23:16] = mixcol_in[31:24]       ^ mul2(mixcol_in[23:16]) ^ mul3(mixcol_in[15:8])  ^ mixcol_in[7:0];
    mixcol[15:8]  = mixcol_in[31:24]       ^ mixcol_in[23:16]       ^ mul2(mixcol_in[15:8])  ^ mul3(mixcol_in[7:0]);
    mixcol[7:0]   = mul3(mixcol_in[31:24]) ^ mixcol_in[23:16]       ^ mixcol_in[15:8]        ^ mul2(mixcol_in[7:0]);
  end
endfunction

//-----------------------------------------------------
// S-Box composite field helpers (same as your snippet)
//-----------------------------------------------------
function [1:0] mulGf22;
  input [1:0] a;
  input [1:0] b;
  begin
    mulGf22[1] = (a[1] & b[1]) ^ (a[0] & b[1]) ^ (a[1] & b[0]);
    mulGf22[0] = (a[1] & b[1]) ^ (a[0] & b[0]);
  end
endfunction

function [3:0] mulGf24;
  input [3:0] operand0;
  input [3:0] operand1;

  reg [1:0] operand0_msb, operand0_lsb;
  reg [1:0] operand1_msb, operand1_lsb;
  reg [1:0] operand0_xor, operand1_xor;
  reg [1:0] mul_msb0_msb1, mul_xor0_xor1, mul_lsb0_lsb1;
  reg [1:0] xPhi;
  begin
    operand0_msb = operand0[3:2];
    operand0_lsb = operand0[1:0];
    operand1_msb = operand1[3:2];
    operand1_lsb = operand1[1:0];

    operand0_xor = operand0_msb ^ operand0_lsb;
    operand1_xor = operand1_msb ^ operand1_lsb;

    mul_msb0_msb1 = mulGf22(operand0_msb, operand1_msb);
    mul_xor0_xor1 = mulGf22(operand0_xor, operand1_xor);
    mul_lsb0_lsb1 = mulGf22(operand0_lsb, operand1_lsb);

    xPhi[1] = mul_msb0_msb1[1] ^ mul_msb0_msb1[0];
    xPhi[0] = mul_msb0_msb1[1];

    mulGf24[3:2] = mul_xor0_xor1 ^ mul_lsb0_lsb1;
    mulGf24[1:0] = xPhi ^ mul_lsb0_lsb1;
  end
endfunction

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

function [7:0] mulGf28Inv;
  input [7:0] invInput;
  reg [7:0] after_imp, imp_inv_in;
  reg [3:0] imp_msb, imp_lsb, square, xLamda;
  reg [3:0] lsb_xor_msb, lsb_mulGf24, xor_branch, inv_branch;
  begin
    after_imp[7] = invInput[7] ^ invInput[5];
    after_imp[6] = invInput[7] ^ invInput[6] ^ invInput[4] ^ invInput[3] ^ invInput[2] ^ invInput[1];
    after_imp[5] = invInput[7] ^ invInput[5] ^ invInput[3] ^ invInput[2];
    after_imp[4] = invInput[7] ^ invInput[5] ^ invInput[3] ^ invInput[2] ^ invInput[1];
    after_imp[3] = invInput[7] ^ invInput[6] ^ invInput[2] ^ invInput[1];
    after_imp[2] = invInput[7] ^ invInput[4] ^ invInput[3] ^ invInput[2] ^ invInput[1];
    after_imp[1] = invInput[6] ^ invInput[4] ^ invInput[1];
    after_imp[0] = invInput[6] ^ invInput[1] ^ invInput[0];

    imp_msb = after_imp[7:4];
    imp_lsb = after_imp[3:0];

    square[3] = imp_msb[3];
    square[2] = imp_msb[3] ^ imp_msb[2];
    square[1] = imp_msb[2] ^ imp_msb[1];
    square[0] = imp_msb[3] ^ imp_msb[1] ^ imp_msb[0];

    xLamda[3] = square[2] ^ square[0];
    xLamda[2] = ^square;
    xLamda[1] = square[3];
    xLamda[0] = square[2];

    lsb_xor_msb  = imp_msb ^ imp_lsb;
    lsb_mulGf24  = mulGf24(lsb_xor_msb, imp_lsb);
    xor_branch   = xLamda ^ lsb_mulGf24;

    case (xor_branch)
      4'h0: inv_branch = 4'h0; 4'h1: inv_branch = 4'h1;
      4'h2: inv_branch = 4'h3; 4'h3: inv_branch = 4'h2;
      4'h4: inv_branch = 4'hF; 4'h5: inv_branch = 4'hC;
      4'h6: inv_branch = 4'h9; 4'h7: inv_branch = 4'hB;
      4'h8: inv_branch = 4'hA; 4'h9: inv_branch = 4'h6;
      4'hA: inv_branch = 4'h8; 4'hB: inv_branch = 4'h7;
      4'hC: inv_branch = 4'h5; 4'hD: inv_branch = 4'hE;
      4'hE: inv_branch = 4'hD; 4'hF: inv_branch = 4'h4;
      default: inv_branch = 4'h0;
    endcase

    imp_inv_in[7:4] = mulGf24(after_imp[7:4], inv_branch);
    imp_inv_in[3:0] = mulGf24(lsb_xor_msb, inv_branch);

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

// encrypt_en=1 => forward S-box (affine(mulInv))
// encrypt_en=0 => inverse S-box (mulInv(affineInv))
function [7:0] aes128_sbox;
  input [7:0] sbox_in;
  input encrypt_en;
  reg [7:0] mulInvResult;
  reg [7:0] affineInvResult;
  reg [7:0] before_mulInv;
  begin
    affineInvResult = affineInv(sbox_in);
    before_mulInv   = encrypt_en ? sbox_in : affineInvResult;
    mulInvResult    = mulGf28Inv(before_mulInv);
    aes128_sbox     = encrypt_en ? affine(mulInvResult) : mulInvResult;
  end
endfunction


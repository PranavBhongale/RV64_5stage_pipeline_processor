from reportlab.lib.pagesizes import A4, landscape
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, KeepTogether
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib import colors
from reportlab.lib.units import mm

OUTPUT = "RV64_Skipped_Extensions_A_FD_C_V.pdf"

# ── palette ──────────────────────────────────────────────────────────────────
C_HDR_BG  = colors.HexColor("#2C2C2A")
C_SEC_BG  = colors.HexColor("#444441")
C_SEC_TXT = colors.HexColor("#D3D1C7")
C_ROW_ALT = colors.HexColor("#F9F8F6")
C_BORDER  = colors.HexColor("#B4B2A9")

COL_OP  = colors.HexColor("#EEEDFE")
COL_RD  = colors.HexColor("#E6F1FB")
COL_FN3 = colors.HexColor("#EAF3DE")
COL_RS1 = colors.HexColor("#FAEEDA")
COL_RS2 = colors.HexColor("#FAECE7")
COL_FN7 = colors.HexColor("#FBEAF0")
COL_IMM = colors.HexColor("#F1EFE8")
COL_AQ  = colors.HexColor("#E1F5EE")  # teal for aq/rl

# badge colors per extension
BADGES = {
    'R':  (colors.HexColor("#EEEDFE"), colors.HexColor("#3C3489")),
    'R4': (colors.HexColor("#FAEEDA"), colors.HexColor("#633806")),
    'I':  (colors.HexColor("#E6F1FB"), colors.HexColor("#0C447C")),
    'S':  (colors.HexColor("#FAEEDA"), colors.HexColor("#633806")),
    'CI': (colors.HexColor("#EAF3DE"), colors.HexColor("#27500A")),
    'CR': (colors.HexColor("#FAECE7"), colors.HexColor("#712B13")),
    'CSS':(colors.HexColor("#FBEAF0"), colors.HexColor("#72243E")),
    'CL': (colors.HexColor("#E1F5EE"), colors.HexColor("#085041")),
    'CS': (colors.HexColor("#FAEEDA"), colors.HexColor("#633806")),
    'CB': (colors.HexColor("#FCEBEB"), colors.HexColor("#791F1F")),
    'CJ': (colors.HexColor("#F1EFE8"), colors.HexColor("#444441")),
    'A':  (colors.HexColor("#E1F5EE"), colors.HexColor("#085041")),
}

# ── helpers ──────────────────────────────────────────────────────────────────
def mono(t, sz=7.2):
    t = str(t)
    return Paragraph(f'<font name="Courier" size="{sz}">{t}</font>',
                     ParagraphStyle('m', fontName='Courier', fontSize=sz, leading=sz+2.5))

def normal(t, sz=7.2):
    t = str(t).replace('&','&amp;').replace('<','&lt;').replace('>','&gt;')
    return Paragraph(t, ParagraphStyle('n', fontName='Helvetica', fontSize=sz, leading=sz+2.5))

def bold(t, sz=8, col=colors.white):
    return Paragraph(f'<b>{t}</b>',
                     ParagraphStyle('b', fontName='Helvetica-Bold', fontSize=sz,
                                    textColor=col, leading=sz+2))

def badge(letter):
    bg, fg = BADGES.get(letter, (colors.HexColor("#F1EFE8"), colors.HexColor("#444441")))
    return Paragraph(f'<b>{letter}</b>',
                     ParagraphStyle('badge', fontName='Helvetica-Bold', fontSize=6.5,
                                    textColor=fg, backColor=bg, leading=8,
                                    borderPadding=2, alignment=1))

def bit_layout(fields):
    cells = [Paragraph(f'<font size="5.5"><b>{lbl}</b></font>',
                       ParagraphStyle('fl', fontName='Helvetica-Bold', fontSize=5.5,
                                      textColor=colors.HexColor("#2C2C2A"),
                                      backColor=col, leading=7, alignment=1, borderPadding=1))
             for lbl, col in fields]
    t = Table([cells], colWidths=[None]*len(fields))
    t.setStyle(TableStyle(
        [('BACKGROUND',(i,0),(i,0),col) for i,(lbl,col) in enumerate(fields)] +
        [('BOX',(0,0),(-1,-1),0.3,C_BORDER),
         ('INNERGRID',(0,0),(-1,-1),0.3,C_BORDER),
         ('TOPPADDING',(0,0),(-1,-1),1),('BOTTOMPADDING',(0,0),(-1,-1),1),
         ('LEFTPADDING',(0,0),(-1,-1),1),('RIGHTPADDING',(0,0),(-1,-1),1)]))
    return t

def sec(title, span=8):
    return [Paragraph(f'<b>{title}</b>',
                      ParagraphStyle('sec', fontName='Helvetica-Bold', fontSize=7.8,
                                     textColor=C_SEC_TXT, leading=10))] + ['']*(span-1)

def ext_header(title, span=8):
    return [Paragraph(f'<b>{title}</b>',
                      ParagraphStyle('exth', fontName='Helvetica-Bold', fontSize=9,
                                     textColor=colors.white, leading=12))] + ['']*(span-1)

HDR = [bold("Mnemonic"), bold("Fmt"), bold("opcode"), bold("funct3"),
       bold("funct7 / imm"), bold("Bit layout [31:0]"), bold("Operation"), bold("Complexity reason")]

CW = [18*mm, 9*mm, 22*mm, 15*mm, 24*mm, 60*mm, 66*mm, 50*mm]

# ── bit layouts ──────────────────────────────────────────────────────────────
def R_lay(f7, op):
    return bit_layout([(f7,COL_FN7),("rs2",COL_RS2),("rs1",COL_RS1),("f3",COL_FN3),("rd",COL_RD),(op,COL_OP)])

def AMO_lay(op):
    return bit_layout([("f5",COL_FN7),("aq",COL_AQ),("rl",COL_AQ),("rs2",COL_RS2),("rs1",COL_RS1),("f3",COL_FN3),("rd",COL_RD),(op,COL_OP)])

def I_lay(op, f3="f3"):
    return bit_layout([("imm[11:0]",COL_IMM),("rs1",COL_RS1),(f3,COL_FN3),("rd",COL_RD),(op,COL_OP)])

def S_lay(op, f3="f3"):
    return bit_layout([("im[11:5]",COL_IMM),("rs2",COL_RS2),("rs1",COL_RS1),(f3,COL_FN3),("im[4:0]",COL_IMM),(op,COL_OP)])

def R4_lay(op):
    return bit_layout([("rs3",COL_FN7),("fmt",COL_RS2),("rs2",COL_RS2),("rs1",COL_RS1),("rm",COL_FN3),("rd",COL_RD),(op,COL_OP)])

# 16-bit compressed layouts (shown as 16-bit word)
def C_lay(fields):
    cells = [Paragraph(f'<font size="5.5"><b>{lbl}</b></font>',
                       ParagraphStyle('fl', fontName='Helvetica-Bold', fontSize=5.5,
                                      textColor=colors.HexColor("#2C2C2A"),
                                      backColor=col, leading=7, alignment=1, borderPadding=1))
             for lbl, col in fields]
    t = Table([cells], colWidths=[None]*len(fields))
    t.setStyle(TableStyle(
        [('BACKGROUND',(i,0),(i,0),col) for i,(lbl,col) in enumerate(fields)] +
        [('BOX',(0,0),(-1,-1),0.3,C_BORDER),
         ('INNERGRID',(0,0),(-1,-1),0.3,C_BORDER),
         ('TOPPADDING',(0,0),(-1,-1),1),('BOTTOMPADDING',(0,0),(-1,-1),1),
         ('LEFTPADDING',(0,0),(-1,-1),1),('RIGHTPADDING',(0,0),(-1,-1),1)]))
    return t

COP = colors.HexColor("#EAF3DE")   # op[1:0] green
CRD = colors.HexColor("#E6F1FB")
CRS = colors.HexColor("#FAEEDA")
CIM = colors.HexColor("#F1EFE8")
CFU = colors.HexColor("#FBEAF0")

def CR():  return C_lay([("funct4",CFU),("rd/rs1",CRD),("rs2",CRS),("op",COP)])
def CI():  return C_lay([("funct3",CFU),("imm",CIM),("rd/rs1",CRD),("imm",CIM),("op",COP)])
def CSS(): return C_lay([("funct3",CFU),("imm",CIM),("rs2",CRS),("op",COP)])
def CIW(): return C_lay([("funct3",CFU),("imm[9:2]",CIM),("rd'",CRD),("op",COP)])
def CL():  return C_lay([("funct3",CFU),("imm",CIM),("rs1'",CRS),("imm",CIM),("rd'",CRD),("op",COP)])
def CS():  return C_lay([("funct3",CFU),("imm",CIM),("rs1'",CRS),("imm",CIM),("rs2'",CRS),("op",COP)])
def CA():  return C_lay([("funct6",CFU),("rd'/rs1'",CRD),("funct2",CFU),("rs2'",CRS),("op",COP)])
def CB():  return C_lay([("funct3",CFU),("off",CIM),("rs1'",CRS),("off",CIM),("op",COP)])
def CJ_l():return C_lay([("funct3",CFU),("jump target[11:1]",CIM),("op",COP)])

def row(mn, fmt, op, f3, f7imm, lay, operation, why):
    return [mono(mn), badge(fmt), mono(op), mono(f3), mono(f7imm), lay, normal(operation), normal(why)]

# ════════════════════════════════════════════════════════════════════════════
# A EXTENSION
# ════════════════════════════════════════════════════════════════════════════
A_data = [
    HDR,
    ext_header("A — Atomic Extension  (RV64A)  |  WHY SKIPPED: requires bus locking / cache coherence, breaks simple pipeline memory stage"),
    sec("A — Load-Reserved / Store-Conditional  (opcode 0101111)"),
    row("LR.W",    "A","0101111","010","00010|aq|rl|00000", AMO_lay("0101111"),
        "rd=Mem[rs1]; reserve address (32-bit)",      "Sets reservation; SC must check — needs memory bus lock"),
    row("LR.D",    "A","0101111","011","00010|aq|rl|00000", AMO_lay("0101111"),
        "rd=Mem[rs1]; reserve address (64-bit)",      "64-bit version — same bus-lock requirement"),
    row("SC.W",    "A","0101111","010","00011|aq|rl|rs2",   AMO_lay("0101111"),
        "if reserved: Mem[rs1]=rs2; rd=0 else rd=1",  "Conditional store — reservation check in MEM stage"),
    row("SC.D",    "A","0101111","011","00011|aq|rl|rs2",   AMO_lay("0101111"),
        "if reserved: Mem[rs1]=rs2; rd=0 else rd=1",  "64-bit conditional store"),
    sec("A — Atomic Memory Operations  (opcode 0101111, funct3=010/011 for W/D)"),
    row("AMOSWAP.W","A","0101111","010","00001|aq|rl", AMO_lay("0101111"),
        "tmp=Mem[rs1]; Mem[rs1]=rs2; rd=tmp",         "Read-modify-write; needs atomic MEM access"),
    row("AMOSWAP.D","A","0101111","011","00001|aq|rl", AMO_lay("0101111"),
        "64-bit atomic swap",                          "Same — 64-bit"),
    row("AMOADD.W", "A","0101111","010","00000|aq|rl", AMO_lay("0101111"),
        "Mem[rs1] += rs2; rd=old value (32-bit)",     "Atomic add — all AMOs stall pipeline in MEM"),
    row("AMOADD.D", "A","0101111","011","00000|aq|rl", AMO_lay("0101111"),
        "Mem[rs1] += rs2; rd=old value (64-bit)",     "64-bit atomic add"),
    row("AMOAND.W", "A","0101111","010","01100|aq|rl", AMO_lay("0101111"),
        "Mem[rs1] &= rs2; rd=old (32-bit)",           "Atomic AND"),
    row("AMOAND.D", "A","0101111","011","01100|aq|rl", AMO_lay("0101111"),
        "Mem[rs1] &= rs2; rd=old (64-bit)",           "64-bit atomic AND"),
    row("AMOOR.W",  "A","0101111","010","01000|aq|rl", AMO_lay("0101111"),
        "Mem[rs1] |= rs2; rd=old (32-bit)",           "Atomic OR"),
    row("AMOOR.D",  "A","0101111","011","01000|aq|rl", AMO_lay("0101111"),
        "Mem[rs1] |= rs2; rd=old (64-bit)",           "64-bit atomic OR"),
    row("AMOXOR.W", "A","0101111","010","00100|aq|rl", AMO_lay("0101111"),
        "Mem[rs1] ^= rs2; rd=old (32-bit)",           "Atomic XOR"),
    row("AMOXOR.D", "A","0101111","011","00100|aq|rl", AMO_lay("0101111"),
        "Mem[rs1] ^= rs2; rd=old (64-bit)",           "64-bit atomic XOR"),
    row("AMOMIN.W", "A","0101111","010","10000|aq|rl", AMO_lay("0101111"),
        "Mem[rs1]=min(Mem,rs2) signed; rd=old",       "Atomic signed min"),
    row("AMOMIN.D", "A","0101111","011","10000|aq|rl", AMO_lay("0101111"),
        "64-bit atomic signed min",                    "64-bit"),
    row("AMOMAX.W", "A","0101111","010","10100|aq|rl", AMO_lay("0101111"),
        "Mem[rs1]=max(Mem,rs2) signed; rd=old",       "Atomic signed max"),
    row("AMOMAX.D", "A","0101111","011","10100|aq|rl", AMO_lay("0101111"),
        "64-bit atomic signed max",                    "64-bit"),
    row("AMOMINU.W","A","0101111","010","11000|aq|rl", AMO_lay("0101111"),
        "Mem[rs1]=min(Mem,rs2) unsigned; rd=old",     "Atomic unsigned min"),
    row("AMOMINU.D","A","0101111","011","11000|aq|rl", AMO_lay("0101111"),
        "64-bit atomic unsigned min",                  "64-bit"),
    row("AMOMAXU.W","A","0101111","010","11100|aq|rl", AMO_lay("0101111"),
        "Mem[rs1]=max(Mem,rs2) unsigned; rd=old",     "Atomic unsigned max"),
    row("AMOMAXU.D","A","0101111","011","11100|aq|rl", AMO_lay("0101111"),
        "64-bit atomic unsigned max",                  "64-bit"),
]

# ════════════════════════════════════════════════════════════════════════════
# F / D EXTENSION
# ════════════════════════════════════════════════════════════════════════════
FD_data = [
    HDR,
    ext_header("F/D — Single & Double Precision Float  (RV64F + RV64D)  |  WHY SKIPPED: separate FP register file (f0–f31), FPU datapath, FP hazard unit"),
    sec("F — FP Loads / Stores  (F=0000111/0100111, D=0000111/0100111 funct3 differs)"),
    row("FLW",  "I","0000111","010","offset", I_lay("0000111","010"), "fd=Mem[rs1+imm] (32-bit float)",    "Loads into FP reg file — separate from int pipeline"),
    row("FLD",  "I","0000111","011","offset", I_lay("0000111","011"), "fd=Mem[rs1+imm] (64-bit double)",   "Double load — FP reg file"),
    row("FSW",  "S","0100111","010","offset", S_lay("0100111","010"), "Mem[rs1+imm]=fs2 (32-bit)",         "FP store — rs2 from FP reg file"),
    row("FSD",  "S","0100111","011","offset", S_lay("0100111","011"), "Mem[rs1+imm]=fs2 (64-bit)",         "Double store"),
    sec("F — FP Arithmetic  (opcode 1010011, fmt=00 single / 01 double)"),
    row("FADD.S",  "R","1010011","rm","0000000", R_lay("0000000","1010011"), "fd=fs1+fs2 (single)",       "FPU add — multicycle EX, separate hazard tracking"),
    row("FADD.D",  "R","1010011","rm","0000001", R_lay("0000001","1010011"), "fd=fs1+fs2 (double)",       "Double precision add"),
    row("FSUB.S",  "R","1010011","rm","0000100", R_lay("0000100","1010011"), "fd=fs1-fs2 (single)",       "FPU subtract"),
    row("FSUB.D",  "R","1010011","rm","0000101", R_lay("0000101","1010011"), "fd=fs1-fs2 (double)",       "Double subtract"),
    row("FMUL.S",  "R","1010011","rm","0001000", R_lay("0001000","1010011"), "fd=fs1*fs2 (single)",       "FPU multiply"),
    row("FMUL.D",  "R","1010011","rm","0001001", R_lay("0001001","1010011"), "fd=fs1*fs2 (double)",       "Double multiply"),
    row("FDIV.S",  "R","1010011","rm","0001100", R_lay("0001100","1010011"), "fd=fs1/fs2 (single)",       "FPU divide — very long latency"),
    row("FDIV.D",  "R","1010011","rm","0001101", R_lay("0001101","1010011"), "fd=fs1/fs2 (double)",       "Double divide"),
    row("FSQRT.S", "R","1010011","rm","0101100", R_lay("0101100","1010011"), "fd=sqrt(fs1) (single)",     "Square root — long latency"),
    row("FSQRT.D", "R","1010011","rm","0101101", R_lay("0101101","1010011"), "fd=sqrt(fs1) (double)",     "Double sqrt"),
    sec("F — Fused Multiply-Add  (4-register R4-type — unique format)"),
    row("FMADD.S",  "R4","1000011","rm","rs3|00", R4_lay("1000011"), "fd=fs1*fs2+fs3 (single)",  "3 FP src regs — new forwarding paths needed"),
    row("FMADD.D",  "R4","1000011","rm","rs3|01", R4_lay("1000011"), "fd=fs1*fs2+fs3 (double)",  "4-operand instruction"),
    row("FMSUB.S",  "R4","1000111","rm","rs3|00", R4_lay("1000111"), "fd=fs1*fs2-fs3 (single)",  "Fused multiply-subtract"),
    row("FMSUB.D",  "R4","1000111","rm","rs3|01", R4_lay("1000111"), "fd=fs1*fs2-fs3 (double)",  "Double"),
    row("FNMADD.S", "R4","1001111","rm","rs3|00", R4_lay("1001111"), "fd=-(fs1*fs2+fs3) (single)","Negated fused MAC"),
    row("FNMADD.D", "R4","1001111","rm","rs3|01", R4_lay("1001111"), "fd=-(fs1*fs2+fs3) (double)","Double"),
    row("FNMSUB.S", "R4","1001011","rm","rs3|00", R4_lay("1001011"), "fd=-(fs1*fs2-fs3) (single)","Negated fused MS"),
    row("FNMSUB.D", "R4","1001011","rm","rs3|01", R4_lay("1001011"), "fd=-(fs1*fs2-fs3) (double)","Double"),
    sec("F/D — Compare, Convert, Move  (opcode 1010011)"),
    row("FEQS.S","R","1010011","010","1010000", R_lay("1010000","1010011"), "rd=(fs1==fs2)?1:0",         "FP compare — result into int reg"),
    row("FEQS.D","R","1010011","010","1010001", R_lay("1010001","1010011"), "rd=(fs1==fs2)?1:0 (double)", "Double compare"),
    row("FLTS.S","R","1010011","001","1010000", R_lay("1010000","1010011"), "rd=(fs1<fs2)?1:0",          "FP less-than"),
    row("FLTS.D","R","1010011","001","1010001", R_lay("1010001","1010011"), "rd=(fs1<fs2)?1:0 (double)", "Double LT"),
    row("FLES.S","R","1010011","000","1010000", R_lay("1010000","1010011"), "rd=(fs1<=fs2)?1:0",         "FP less-or-equal"),
    row("FLES.D","R","1010011","000","1010001", R_lay("1010001","1010011"), "rd=(fs1<=fs2)?1:0 (double)","Double LE"),
    row("FCVT.W.S", "R","1010011","rm","1100000|00000", R_lay("1100000","1010011"), "rd=int(fs1) signed 32",  "FP->int conversion crosses reg files"),
    row("FCVT.WU.S","R","1010011","rm","1100000|00001", R_lay("1100000","1010011"), "rd=uint(fs1) 32-bit",    "FP->uint"),
    row("FCVT.L.D", "R","1010011","rm","1100001|00010", R_lay("1100001","1010011"), "rd=int64(fd1)",          "Double->int64 (RV64D)"),
    row("FCVT.S.W", "R","1010011","rm","1101000|00000", R_lay("1101000","1010011"), "fd=float(rs1) signed 32","int->FP crosses reg files"),
    row("FCVT.D.L", "R","1010011","rm","1101001|00010", R_lay("1101001","1010011"), "fd=double(rs1) int64",   "int64->double (RV64D)"),
    row("FMV.X.W",  "R","1010011","000","1110000|00000", R_lay("1110000","1010011"), "rd=bitcast(fs1) 32-bit","Bit-move FP->int reg"),
    row("FMV.W.X",  "R","1010011","000","1111000|00000", R_lay("1111000","1010011"), "fd=bitcast(rs1) 32-bit","Bit-move int->FP reg"),
    row("FMV.X.D",  "R","1010011","000","1110001|00000", R_lay("1110001","1010011"), "rd=bitcast(fd1) 64-bit","Double bit-move FP->int (RV64D)"),
    row("FMV.D.X",  "R","1010011","000","1111001|00000", R_lay("1111001","1010011"), "fd=bitcast(rs1) 64-bit","Double bit-move int->FP (RV64D)"),
    row("FCLASS.S","R","1010011","001","1110000|00000", R_lay("1110000","1010011"), "rd=class(fs1) bitmask",  "Classify FP (NaN, inf, zero, etc.)"),
    row("FCLASS.D","R","1010011","001","1110001|00000", R_lay("1110001","1010011"), "rd=class(fd1) bitmask",  "Double classify"),
    row("FSGNJ.S","R","1010011","000","0010000", R_lay("0010000","1010011"), "fd=|fs1| with sign of fs2","FP sign inject"),
    row("FSGNJ.D","R","1010011","000","0010001", R_lay("0010001","1010011"), "fd=|fd1| with sign of fd2","Double sign inject"),
    row("FMIN.S","R","1010011","000","0010100", R_lay("0010100","1010011"), "fd=min(fs1,fs2)",           "FP minimum"),
    row("FMIN.D","R","1010011","000","0010101", R_lay("0010101","1010011"), "fd=min(fd1,fd2)",           "Double minimum"),
    row("FMAX.S","R","1010011","001","0010100", R_lay("0010100","1010011"), "fd=max(fs1,fs2)",           "FP maximum"),
    row("FMAX.D","R","1010011","001","0010101", R_lay("0010101","1010011"), "fd=max(fd1,fd2)",           "Double maximum"),
]

# ════════════════════════════════════════════════════════════════════════════
# C EXTENSION
# ════════════════════════════════════════════════════════════════════════════
C_data = [
    HDR,
    ext_header("C — Compressed Extension (16-bit instructions)  |  WHY SKIPPED: variable length (16/32-bit mix) breaks IF stage — needs alignment buffer & PC realignment logic"),
    sec("C — Quadrant 0  (op[1:0]=00) — Loads & Stores"),
    row("C.ADDI4SPN","CIW","00","000","nzuimm[9:2]", CIW(), "rd'=sp+uimm (rd'=x8-x15)",       "Compressed imm add to sp"),
    row("C.FLD",     "CL", "00","001","uimm[5:3|7:6]",CL(),  "fd'=Mem[rs1'+uimm] (double)",    "FP load — also needs FP reg file"),
    row("C.LW",      "CL", "00","010","uimm[5:3|2|6]", CL(), "rd'=Mem[rs1'+uimm] 32-bit",      "Compressed word load"),
    row("C.LD",      "CL", "00","011","uimm[5:3|7:6]", CL(), "rd'=Mem[rs1'+uimm] 64-bit",      "Compressed dword load (RV64C)"),
    row("C.FSD",     "CS", "00","101","uimm[5:3|7:6]", CS(), "Mem[rs1'+uimm]=fs2' (double)",   "Compressed FP store"),
    row("C.SW",      "CS", "00","110","uimm[5:3|2|6]", CS(), "Mem[rs1'+uimm]=rs2' 32-bit",     "Compressed word store"),
    row("C.SD",      "CS", "00","111","uimm[5:3|7:6]", CS(), "Mem[rs1'+uimm]=rs2' 64-bit",     "Compressed dword store (RV64C)"),
    sec("C — Quadrant 1  (op[1:0]=01) — Branches, Jumps, Immediates"),
    row("C.NOP",     "CI", "01","000","0",             CI(),  "NOP (ADDI x0,x0,0)",             "Expands to full NOP"),
    row("C.ADDI",    "CI", "01","000","nzimm[5|4:0]",  CI(),  "rd+=nzimm (rd!=x0)",             "Compressed add immediate"),
    row("C.ADDIW",   "CI", "01","001","imm[5|4:0]",    CI(),  "rd=sext(rd[31:0]+imm) (RV64C)",  "Compressed addiw"),
    row("C.LI",      "CI", "01","010","imm[5|4:0]",    CI(),  "rd=sext(imm)",                   "Load immediate"),
    row("C.ADDI16SP","CI", "01","011","nzimm[9|4|6|8:7|5]",CI(),"sp+=nzimm*16",               "Stack pointer adjust"),
    row("C.LUI",     "CI", "01","011","nzimm[17|16:12]",CI(), "rd=nzimm<<12",                  "Load upper imm (rd!=x2)"),
    row("C.SRLI",    "CB", "01","100","shamt[5|4:0]",  CB(),  "rd'=rd'>>shamt (logical)",       "Compressed shift right logical"),
    row("C.SRAI",    "CB", "01","100","shamt[5|4:0]",  CB(),  "rd'=rd'>>shamt (arithmetic)",    "Compressed shift right arith"),
    row("C.ANDI",    "CB", "01","100","imm[5|4:0]",    CB(),  "rd'=rd'&sext(imm)",              "Compressed AND immediate"),
    row("C.SUB",     "CA", "01","100","—",             CA(),  "rd'=rd'-rs2'",                   "Compressed subtract"),
    row("C.XOR",     "CA", "01","100","—",             CA(),  "rd'=rd'^rs2'",                   "Compressed XOR"),
    row("C.OR",      "CA", "01","100","—",             CA(),  "rd'=rd'|rs2'",                   "Compressed OR"),
    row("C.AND",     "CA", "01","100","—",             CA(),  "rd'=rd'&rs2'",                   "Compressed AND"),
    row("C.SUBW",    "CA", "01","100","—",             CA(),  "rd'=sext((rd'-rs2')[31:0]) RV64", "Compressed subw"),
    row("C.ADDW",    "CA", "01","100","—",             CA(),  "rd'=sext((rd'+rs2')[31:0]) RV64", "Compressed addw"),
    row("C.J",       "CJ", "01","101","offset[11:1]",  CJ_l(),"PC+=sext(offset<<1)",            "Compressed jump"),
    row("C.BEQZ",    "CB", "01","110","offset[8|4:3|7:6|2:1|5]",CB(),"if rd'==0: PC+=sext(off)","Compressed branch EQ zero"),
    row("C.BNEZ",    "CB", "01","111","offset[8|4:3|7:6|2:1|5]",CB(),"if rd'!=0: PC+=sext(off)","Compressed branch NE zero"),
    sec("C — Quadrant 2  (op[1:0]=10) — Stack Loads/Stores, Register Ops"),
    row("C.SLLI",    "CI", "10","000","shamt[5|4:0]",  CI(),  "rd=rd<<shamt",                   "Compressed shift left"),
    row("C.FLDSP",   "CI", "10","001","uimm[5|4:3|8:6]",CI(), "fd=Mem[sp+uimm] double",         "FP stack load"),
    row("C.LWSP",    "CI", "10","010","uimm[5|4:2|7:6]",CI(), "rd=Mem[sp+uimm] 32-bit",         "Stack-relative word load"),
    row("C.LDSP",    "CI", "10","011","uimm[5|4:3|8:6]",CI(), "rd=Mem[sp+uimm] 64-bit (RV64C)", "Stack-relative dword load"),
    row("C.JR",      "CR", "10","100","—",             CR(),  "PC=rs1 (rs2=0, rd=0)",            "Compressed jump register"),
    row("C.MV",      "CR", "10","100","—",             CR(),  "rd=rs2",                          "Compressed move"),
    row("C.EBREAK",  "CR", "10","100","—",             CR(),  "Breakpoint",                      "Compressed ebreak"),
    row("C.JALR",    "CR", "10","100","—",             CR(),  "ra=PC+2; PC=rs1",                 "Compressed JALR — PC+2 not +4!"),
    row("C.ADD",     "CR", "10","100","—",             CR(),  "rd=rd+rs2",                       "Compressed add"),
    row("C.FSDSP",   "CSS","10","101","uimm[5:3|8:6]", CSS(), "Mem[sp+uimm]=fs2 double",         "FP stack store"),
    row("C.SWSP",    "CSS","10","110","uimm[5:2|7:6]", CSS(), "Mem[sp+uimm]=rs2 32-bit",         "Stack-relative word store"),
    row("C.SDSP",    "CSS","10","111","uimm[5:3|8:6]", CSS(), "Mem[sp+uimm]=rs2 64-bit (RV64C)", "Stack-relative dword store"),
]

# ════════════════════════════════════════════════════════════════════════════
# V EXTENSION (summary — too many to list fully)
# ════════════════════════════════════════════════════════════════════════════
V_data = [
    HDR,
    ext_header("V — Vector Extension (RVV 1.0)  |  WHY SKIPPED: completely different execution model — vector register file, vtype CSR, variable-length ops, not compatible with simple 5-stage pipeline"),
    sec("V — Configuration  (opcode 1010111)"),
    row("VSETVLI",  "I","1010111","111","zimm[10:0]",  I_lay("1010111","111"), "vl=min(rs1, vlmax); vtype=zimm","Sets vector length & type — no int equivalent"),
    row("VSETIVLI", "I","1010111","111","zimm|uimm",   I_lay("1010111","111"), "vl=min(uimm, vlmax); vtype=zimm","Immediate vector length config"),
    row("VSETVL",   "R","1010111","111","1xxxxxx",     R_lay("1xxxxxx","1010111"),"vl=min(rs1,rs2[vlmax]); vtype=rs2","Register-based vtype"),
    sec("V — Vector Loads (opcode 0000111) — unit/strided/indexed variants"),
    row("VLE8.V",   "I","0000111","000","nf|mew|mop|vm|lumop", I_lay("0000111","000"),"vd=Mem[rs1..] 8-bit elements", "Loads entire vector reg — width depends on vl"),
    row("VLE16.V",  "I","0000111","101","—",           I_lay("0000111","101"), "vd=Mem[rs1..] 16-bit elements","Variable count from vl CSR"),
    row("VLE32.V",  "I","0000111","110","—",           I_lay("0000111","110"), "vd=Mem[rs1..] 32-bit elements",""),
    row("VLE64.V",  "I","0000111","111","—",           I_lay("0000111","111"), "vd=Mem[rs1..] 64-bit elements",""),
    row("VLSE64.V", "I","0000111","111","stride",      I_lay("0000111","111"), "vd=strided Mem load 64-bit",    "Strided — rs2=byte stride"),
    row("VLUXEI64.V","R","0000111","111","indexed",    R_lay("xxxxxxx","0000111"),"vd=indexed gather load",      "Indexed — rs2=vector of offsets"),
    sec("V — Vector Stores (opcode 0100111)"),
    row("VSE8.V",   "S","0100111","000","—",           S_lay("0100111","000"), "Mem[rs1..]=vs3 8-bit",          "Stores full vector register"),
    row("VSE64.V",  "S","0100111","111","—",           S_lay("0100111","111"), "Mem[rs1..]=vs3 64-bit",         "Width & count from vl/vtype"),
    row("VSSE64.V", "S","0100111","111","stride",      S_lay("0100111","111"), "strided store 64-bit",          "rs2=stride"),
    sec("V — Vector Arithmetic (opcode 1010111) — representative subset"),
    row("VADD.VV",  "R","1010111","000","000000|vm", R_lay("000000","1010111"), "vd=vs2+vs1 (all elements)",    "Parallel add — vl elements processed"),
    row("VADD.VX",  "R","1010111","100","000000|vm", R_lay("000000","1010111"), "vd=vs2+rs1 (scalar broadcast)","Scalar broadcast add"),
    row("VADD.VI",  "I","1010111","011","000000|vm", I_lay("1010111","011"),    "vd=vs2+imm",                   "Immediate broadcast add"),
    row("VSUB.VV",  "R","1010111","000","000010|vm", R_lay("000010","1010111"), "vd=vs2-vs1",                   "Vector subtract"),
    row("VMUL.VV",  "R","1010111","010","100101|vm", R_lay("100101","1010111"), "vd=vs2*vs1 (low half)",        "Vector multiply low"),
    row("VDIV.VV",  "R","1010111","010","100001|vm", R_lay("100001","1010111"), "vd=vs2/vs1 (signed)",          "Vector divide — very long latency"),
    row("VAND.VV",  "R","1010111","000","001001|vm", R_lay("001001","1010111"), "vd=vs2&vs1",                   "Vector AND"),
    row("VOR.VV",   "R","1010111","000","001010|vm", R_lay("001010","1010111"), "vd=vs2|vs1",                   "Vector OR"),
    row("VXOR.VV",  "R","1010111","000","001011|vm", R_lay("001011","1010111"), "vd=vs2^vs1",                   "Vector XOR"),
    row("VFADD.VV", "R","1010111","001","000000|vm", R_lay("000000","1010111"), "vd=vs2+vs1 (float)",           "Vector FP add — needs FPU array"),
    row("VFMUL.VV", "R","1010111","001","100100|vm", R_lay("100100","1010111"), "vd=vs2*vs1 (float)",           "Vector FP multiply"),
    row("VMSEQ.VV", "R","1010111","000","011000|vm", R_lay("011000","1010111"), "vd[i]=(vs2[i]==vs1[i])?1:0",  "Vector compare to mask"),
    row("VMERGE.VVM","R","1010111","000","010111|1",  R_lay("010111","1010111"), "vd[i]=mask?vs1[i]:vs2[i]",   "Masked merge"),
    row("VREDSUM.VS","R","1010111","010","000001|vm", R_lay("000001","1010111"), "vd[0]=sum(vs2[0..vl-1])",     "Reduction — sequential dependency"),
]

# ── build per-extension tables ────────────────────────────────────────────
def build_table(data, sec_indices, ext_indices):
    t = Table(data, colWidths=CW, repeatRows=1)
    ts = TableStyle([
        ('BACKGROUND',(0,0),(-1,0), C_HDR_BG),
        ('TEXTCOLOR',(0,0),(-1,0), colors.white),
        ('FONTSIZE',(0,0),(-1,-1), 7.2),
        ('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white, C_ROW_ALT]),
        ('BOX',(0,0),(-1,-1),0.5,C_BORDER),
        ('INNERGRID',(0,0),(-1,-1),0.3,C_BORDER),
        ('VALIGN',(0,0),(-1,-1),'MIDDLE'),
        ('TOPPADDING',(0,0),(-1,-1),2.5),('BOTTOMPADDING',(0,0),(-1,-1),2.5),
        ('LEFTPADDING',(0,0),(-1,-1),3),('RIGHTPADDING',(0,0),(-1,-1),3),
    ])
    for i in sec_indices:
        ts.add('SPAN',(0,i),(-1,i))
        ts.add('BACKGROUND',(0,i),(-1,i), C_SEC_BG)
        ts.add('TEXTCOLOR',(0,i),(-1,i), C_SEC_TXT)
    for i in ext_indices:
        ts.add('SPAN',(0,i),(-1,i))
        ts.add('BACKGROUND',(0,i),(-1,i), C_HDR_BG)
        ts.add('TEXTCOLOR',(0,i),(-1,i), colors.white)
    t.setStyle(ts)
    return t

# ── styles ────────────────────────────────────────────────────────────────
title_s = ParagraphStyle('t', fontName='Helvetica-Bold', fontSize=14,
                          textColor=colors.HexColor("#2C2C2A"), leading=18)
sub_s   = ParagraphStyle('s', fontName='Helvetica', fontSize=8.5,
                          textColor=colors.HexColor("#5F5E5A"), leading=13)
h2_s    = ParagraphStyle('h2', fontName='Helvetica-Bold', fontSize=11,
                          textColor=colors.HexColor("#2C2C2A"), leading=15)
note_s  = ParagraphStyle('note', fontName='Helvetica', fontSize=7.8,
                          textColor=colors.HexColor("#5F5E5A"), leading=12, leftIndent=6)

def reason_box(text):
    return Paragraph(f'<b>Why skipped:</b> {text}', note_s)

# ── legend ────────────────────────────────────────────────────────────────
leg_fields = [("opcode",COL_OP),("rd",COL_RD),("funct3",COL_FN3),
              ("rs1",COL_RS1),("rs2",COL_RS2),("funct7/imm",COL_FN7),("aq/rl",COL_AQ),("imm",COL_IMM)]
leg_cells = [Paragraph(f'<font name="Helvetica-Bold" size="6.5" color="#2C2C2A"> {lbl} </font>',
                        ParagraphStyle('l', backColor=col, fontSize=6.5, leading=9, borderPadding=2))
             for lbl,col in leg_fields]
leg_t = Table([leg_cells])
leg_t.setStyle(TableStyle([
    ('BOX',(0,0),(-1,-1),0.3,C_BORDER),('INNERGRID',(0,0),(-1,-1),0.3,C_BORDER),
    ('TOPPADDING',(0,0),(-1,-1),2),('BOTTOMPADDING',(0,0),(-1,-1),2),
    ('LEFTPADDING',(0,0),(-1,-1),3),('RIGHTPADDING',(0,0),(-1,-1),3),
    ('VALIGN',(0,0),(-1,-1),'MIDDLE'),
] + [('BACKGROUND',(i,0),(i,0),col) for i,(lbl,col) in enumerate(leg_fields)]))

# ── document ──────────────────────────────────────────────────────────────
doc = SimpleDocTemplate(OUTPUT, pagesize=landscape(A4),
                        leftMargin=10*mm, rightMargin=10*mm,
                        topMargin=12*mm, bottomMargin=10*mm)

A_sec   = [1,2,6]
FD_sec  = [1,2,6,15,24,33]
C_sec   = [1,2,10,27]
V_sec   = [1,2,6,10,15]

story = [
    Paragraph("RV64 — Skipped Extensions Decoding Reference", title_s),
    Spacer(1,2*mm),
    Paragraph("Extensions deliberately excluded from 5-stage pipeline implementation to reduce complexity. "
              "Kept for reference — to know exactly what you are not implementing.", sub_s),
    Spacer(1,2*mm),
    leg_t,
    Spacer(1,4*mm),

    Paragraph("A — Atomic Extension", h2_s),
    Spacer(1,1.5*mm),
    reason_box("LR/SC need a reservation set (extra state) and the MEM stage must do an atomic read-modify-write — "
               "impossible without bus locking or cache coherence. AMO instructions cannot be split across pipeline stages safely."),
    Spacer(1,2*mm),
    build_table(A_data, A_sec, [1]),
    Spacer(1,5*mm),

    Paragraph("F/D — Single & Double Precision Floating Point", h2_s),
    Spacer(1,1.5*mm),
    reason_box("Requires a completely separate FP register file (f0–f31, each 64-bit), FPU in EX stage, "
               "FP-specific hazard detection, and cross-file forwarding (FMV instructions cross between int and FP). "
               "The R4-type fused multiply-add (FMADD etc.) needs 3 source registers — a new forwarding path your pipeline doesn't have."),
    Spacer(1,2*mm),
    build_table(FD_data, FD_sec, [1]),
    Spacer(1,5*mm),

    Paragraph("C — Compressed Extension (16-bit instructions)", h2_s),
    Spacer(1,1.5*mm),
    reason_box("Instructions are 16 or 32 bits — the fetch stage can no longer assume 4-byte alignment. "
               "You need an instruction buffer, a 16/32-bit detector, and PC logic that can advance by 2 or 4. "
               "C.JALR returns to PC+2 (not PC+4), breaking standard link-register assumptions. "
               "Only 8 registers (x8–x15) are addressable in most compressed formats."),
    Spacer(1,2*mm),
    build_table(C_data, C_sec, [1]),
    Spacer(1,5*mm),

    Paragraph("V — Vector Extension (RVV 1.0)", h2_s),
    Spacer(1,1.5*mm),
    reason_box("Completely different execution model: vl (vector length) and vtype CSRs control how many elements "
               "each instruction processes. Needs a vector register file (32×VLEN bits), a multi-lane execution unit, "
               "and element-level masking. A single VLE64.V can transfer hundreds of bytes — the MEM stage cannot handle this "
               "as a single pipeline transaction. Incompatible with a simple 5-stage design without a complete redesign."),
    Spacer(1,2*mm),
    build_table(V_data, V_sec, [1]),
]

doc.build(story)
print("Done:", OUTPUT)



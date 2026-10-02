/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Protocol Engine State Machine (PESM)
 * Tiny Tapeout CMOS5L - Jane Street Protocol Emulator ASIC Competition
 * 
 * (ეს არის კომენტარი, რომელიც მიუთითებს ლიცენზიას და პროექტის სახელს)[cite: 1]
 */

// მიუთითებს, რომ ყველა სიგნალი (wire), რომელიც წინასწარ არ არის გამოცხადებული, არის შეცდომა (კარგი პრაქტიკაა შეცდომების თავიდან ასაცილებლად).[cite: 1]
`default_nettype none 

// 'module' არის კოდის ძირითადი ბლოკი, როგორც 'class' ან 'function' პროგრამირებაში. აქ ვიწყებთ "protocol_engine"-ის აღწერას.[cite: 1]
module protocol_engine (
    input  wire [7:0] ui_in,    // 8-ბიტიანი შემავალი სიგნალები (Input) მომხმარებლისგან[cite: 1]
    output wire [7:0] uo_out,   // 8-ბიტიანი გამომავალი სიგნალები (Output) მომხმარებლისკენ[cite: 1]
    input  wire [7:0] uio_in,   // 8-ბიტიანი ორმხრივი (in/out) შემავალი ნაწილი[cite: 1]
    output wire [7:0] uio_out,  // 8-ბიტიანი ორმხრივი (in/out) გამომავალი ნაწილი[cite: 1]
    output wire [7:0] uio_oe,   // 8-ბიტიანი სიგნალი, რომელიც წყვეტს ორმხრივი პინები შეტანაზე (in) იმუშაოს თუ გამოტანაზე (out) (Output Enable)[cite: 1]
    input  wire       ena,      // ჩართვის (Enable) სიგნალი, 1 ბიტი[cite: 1]
    input  wire       clk,      // საათის (Clock) სიგნალი, რომელიც მართავს სქემის რიტმს, 1 ბიტი[cite: 1]
    input  wire       rst_n     // რესეტის (Reset) სიგნალი, 'n' ნიშნავს რომ აქტიურია 0-ზე (Negative edge), 1 ბიტი[cite: 1]
);

    // შიდა ცვლადები (რეგისტრები), რომლებიც ინახავენ კონფიგურაციის პარამეტრებს[cite: 1]
    reg [15:0] cfg_clkdiv_int;  // საათის სიხშირის გამყოფის მთელი ნაწილი (16 ბიტი)[cite: 1]
    reg [7:0]  cfg_clkdiv_frac; // საათის სიხშირის გამყოფის წილადი ნაწილი (8 ბიტი)[cite: 1]
    reg [4:0]  cfg_wrap_top;    // ლოპის (ციკლის) ზედა საზღვარი ინსტრუქციებისთვის (5 ბიტი)[cite: 1]
    reg [4:0]  cfg_wrap_bottom; // ლოპის ქვედა საზღვარი ინსტრუქციებისთვის (5 ბიტი)[cite: 1]
    reg [1:0]  cfg_shift_dir;   // მონაცემების გადანაცვლების (Shift) მიმართულება: მარცხნივ თუ მარჯვნივ (2 ბიტი)[cite: 1]
    reg        cfg_autopull;    // ავტომატური Pull (მონაცემის ამოღება FIFO-დან) ჩართვა/გამორთვა (1 ბიტი)[cite: 1]
    reg        cfg_autopush;    // ავტომატური Push (მონაცემის ჩაგდება FIFO-ში) ჩართვა/გამორთვა (1 ბიტი)[cite: 1]
    reg [4:0]  cfg_pull_thresh; // რა ზღვარზე უნდა მოხდეს Pull (5 ბიტი)[cite: 1]
    reg [4:0]  cfg_push_thresh; // რა ზღვარზე უნდა მოხდეს Push (5 ბიტი)[cite: 1]
    reg [3:0]  cfg_side_count;  // რამდენი პინი გამოიყენება გვერდითი (Side-set) ოპერაციებისთვის (4 ბიტი)[cite: 1]
    reg        cfg_side_oe;     // გვერდითი პინების Output Enable კონტროლი (1 ბიტი)[cite: 1]

    wire tick; // 1-ბიტიანი სადენი, რომელიც აღნიშნავს "ტიკს" (პულსს) საათის გამყოფიდან[cite: 1]
    
    // საათის გამყოფი მოდულის გამოძახება. ის იღებს მთავარ `clk`-ს და აგენერირებს შენელებულ `tick`-ს[cite: 1]
    protocol_clock_divider clock_divider (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_clkdiv_int(cfg_clkdiv_int),
        .cfg_clkdiv_frac(cfg_clkdiv_frac),
        .tick(tick)
    );

    // ძრავის ძირითადი შიდა რეგისტრები[cite: 1]
    reg [4:0]  pc;             // Program Counter - მიუთითებს მიმდინარე ინსტრუქციის მისამართს (5 ბიტი, მაქს. 32 ინსტრუქცია)[cite: 1]
    reg [15:0] instr;          // მიმდინარე ინსტრუქციის კოდი, რომელსაც ახლა ასრულებს (16 ბიტი)[cite: 1]
    wire [15:0] imem_read_data;// სადენი, რომელზეც მოდის ინსტრუქციების მეხსიერებიდან წაკითხული მონაცემი[cite: 1]
    reg [31:0] osr;            // Output Shift Register - ინახავს მონაცემებს, რომლებიც უნდა გავიდეს გარეთ (32 ბიტი)[cite: 1]
    reg [31:0] isr;            // Input Shift Register - აგროვებს გარედან შემოსულ მონაცემებს (32 ბიტი)[cite: 1]
    reg [4:0]  osr_count;      // ითვლის რამდენი ბიტი გავიდა OSR-დან (5 ბიტი)[cite: 1]
    reg [4:0]  isr_count;      // ითვლის რამდენი ბიტი შემოვიდა ISR-ში (5 ბიტი)[cite: 1]
    reg [7:0]  x_reg;          // დამხმარე რეგისტრი X, ძირითადად ციკლების დასათვლელად (8 ბიტი)[cite: 1]
    reg [7:0]  y_reg;          // დამხმარე რეგისტრი Y (8 ბიტი)[cite: 1]
    reg [7:0]  pin_out;        // რა მნიშვნელობები უნდა გავიდეს გამომავალ პინებზე (8 ბიტი)[cite: 1]
    reg [7:0]  pin_oe;         // პინების მიმართულების კონტროლი (1=გამომავალი, 0=შემავალი)[cite: 1]
    reg [15:0] delay_cnt;      // დაყოვნების (Delay) მრიცხველი, ლოდინისთვის (16 ბიტი)[cite: 1]
    reg [1:0]  state;          // მიმდინარე მდგომარეობა (მაგ. ინსტრუქციის წაკითხვა თუ შესრულება) (2 ბიტი)[cite: 1]
    reg [1:0]  next_state;     // შემდეგი მდგომარეობა (2 ბიტი)[cite: 1]
    reg        irq_pending;    // მონიშნულია თუ არა წყვეტა (Interrupt) (1 ბიტი)[cite: 1]
    reg [7:0]  host_fifo_data; // ჰოსტთან (მთავარ კომპიუტერთან) მონაცემთა გაცვლის დროებითი ბუფერი[cite: 1]
    reg [7:0]  pin_in_prev;    // ინახავს შემომავალი პინების წინა მნიშვნელობას ცვლილების აღმოსაჩენად[cite: 1]
    reg [7:0]  wait_rise_pending; // აღრიცხავს, რომელ პინებზე მოხდა 0-დან 1-ზე გადასვლა (Rise)[cite: 1]
    reg [7:0]  wait_fall_pending; // აღრიცხავს, რომელ პინებზე მოხდა 1-დან 0-ზე ჩამოსვლა (Fall)[cite: 1]

    // ნიღაბი (Mask) გვერდითი პინებისთვის (Side-set). განსაზღვრავს რომელი პინებია დაჯავშნული ამისთვის[cite: 1]
    reg [3:0] side_mask;
    always @(*) begin : side_mask_decode // ეს ბლოკი მუდმივად გამოითვლის ნიღაბს `cfg_side_count`-ის მიხედვით[cite: 1]
        case (cfg_side_count) // ამოწმებს გვერდითი პინების რაოდენობას[cite: 1]
            4'd0: side_mask = 4'b0000; // თუ 0-ია, არცერთი პინი არ გამოიყენება[cite: 1]
            4'd1: side_mask = 4'b0001; // თუ 1-ია, მხოლოდ 1 პინი გამოიყენება (მარჯვენა ბიტი)[cite: 1]
            4'd2: side_mask = 4'b0011; // 2 პინი[cite: 1]
            4'd3: side_mask = 4'b0111; // 3 პინი[cite: 1]
            default: side_mask = 4'b1111; // სხვა შემთხვევაში მაქსიმუმ 4 პინი[cite: 1]
        endcase
    end

    // მუდმივები (ლოკალური პარამეტრები) State Machine-ისთვის (მდგომარეობების მანქანა)[cite: 1]
    localparam S_FETCH = 2'd0; // მდგომარეობა 0: ინსტრუქციის მოტანა მეხსიერებიდან (Fetch)[cite: 1]
    localparam S_EXEC  = 2'd1; // მდგომარეობა 1: ინსტრუქციის შესრულება (Execute)[cite: 1]
    localparam S_DELAY = 2'd2; // მდგომარეობა 2: დაყოვნება (Delay)[cite: 1]

    // FIFO (First-In, First-Out) რიგის ცვლადები მონაცემთა გასაგზავნად (tx) და მისაღებად (rx)[cite: 1]
    reg [3:0] tx_wr, tx_rd, tx_count; // ჩაწერის მაჩვენებელი, წაკითხვის მაჩვენებელი, ელემენტების რაოდენობა TX-ში[cite: 1]
    reg [3:0] rx_wr, rx_rd, rx_count; // იგივე RX (მიმღები) FIFO-სთვის[cite: 1]
    wire [7:0] tx_fifo_data;  // სადენი, რომელზეც მოდის მონაცემი TX FIFO-დან[cite: 1]
    wire [7:0] rx_fifo_data;  // სადენი, რომელზეც მოდის მონაცემი RX FIFO-დან[cite: 1]
    wire tx_empty = (tx_count == 4'd0); // 1-ია, თუ TX FIFO ცარიელია (0 ელემენტია)[cite: 1]
    wire rx_full  = (rx_count == 4'd8); // 1-ია, თუ RX FIFO სავსეა (8 ელემენტია)[cite: 1]
    
    // ლოგიკა, რომელიც იგებს რას ითხოვს ჰოსტი (მთავარი კომპიუტერი)[cite: 1]
    wire host_fifo_mode = (~uio_in[3]) & uio_in[2]; // ჰოსტი FIFO რეჟიმშია?[cite: 1]
    wire host_write_req = host_fifo_mode & uio_in[0]; // ჰოსტს მონაცემის ჩაწერა უნდა?[cite: 1]
    wire host_read_req  = host_fifo_mode & uio_in[1]; // ჰოსტს მონაცემის წაკითხვა უნდა?[cite: 1]
    wire rx_dequeue = host_read_req && (rx_count != 4'd0); // ამოვიღოთ თუ არა RX-დან ელემენტი[cite: 1]
    wire [7:0] protocol_in = {ui_in[3:0], uio_in[7:4]}; // აერთიანებს შემავალ პინებს ერთ 8-ბიტიან სიგნალად[cite: 1]

    // ავტომატური Pull და Push ლოგიკის შემოწმება[cite: 1]
    wire autopull_hit = cfg_autopull && (osr_count <= cfg_pull_thresh) && !tx_empty 
                        && (instr[15:12] == 4'h4); // უნდა ამოვიღოთ თუ არა ავტომატურად OSR-ში? მხოლოდ OUT ინსტრუქციისას[cite: 1]
    wire autopush_hit = cfg_autopush && (isr_count >= cfg_push_thresh) && 
                        (!rx_full || rx_dequeue)
                        && (instr[15:12] == 4'h3); // უნდა ჩავაგდოთ თუ არა ავტომატურად RX-ში? მხოლოდ IN ინსტრუქციისას[cite: 1]

    // OSR-ის (გამომავალი რეგისტრის) მნიშვნელობის მომზადება[cite: 1]
    wire [31:0] tx_fifo_word = cfg_shift_dir == 2'd0 ? 
                               {24'b0, tx_fifo_data} : 
                               {tx_fifo_data, 24'b0}; // ამზადებს ახალ 32-ბიტიან სიტყვას TX FIFO-დან მიმართულების მიხედვით[cite: 1]
    wire [31:0] osr_eff       = autopull_hit ? tx_fifo_word : osr; // თუ Autopull-ია, ახალ მონაცემს იღებს, თორემ ძველ OSR-ს[cite: 1]
    wire        out_bit       = cfg_shift_dir == 2'd0 ? osr_eff[0] : osr_eff[31]; // იღებს გასაგზავნ ბიტს (მარჯვნიდან ან მარცხნიდან)[cite: 1]
    wire [4:0]  osr_count_eff = autopull_hit ? 5'd8 : osr_count; // ანახლებს OSR ბიტების მთვლელს[cite: 1]

    // ინსტრუქციების ჩატვირთვის (Load) რეჟიმის ცვლადები[cite: 1]
    reg [15:0] load_shift; // ინსტრუქციის ბიტების შემგროვებელი (16 ბიტი)[cite: 1]
    reg [7:0]  cfg_shift;  // კონფიგურაციის ბიტების შემგროვებელი (8 ბიტი)[cite: 1]
    reg [3:0]  load_bit;   // ითვლის მერამდენე ბიტს იღებს ინსტრუქციისთვის[cite: 1]
    reg [2:0]  cfg_bit;    // ითვლის მერამდენე ბიტს იღებს კონფიგურაციისთვის[cite: 1]
    reg [4:0]  load_addr;  // მეხსიერების მისამართი, სადაც იწერება ინსტრუქცია[cite: 1]
    reg        host_clk_d; // ჰოსტის საათის სიგნალის წინა მდგომარეობა (დაყოვნებული)[cite: 1]
    reg        load_mode;  // ჩატვირთვის რეჟიმი აქტიურია თუ არა[cite: 1]
    reg        uio3_d;     // uio_in[3] პინის წინა მდგომარეობა[cite: 1]
    wire       host_clk_rise = uio_in[1] & ~host_clk_d; // ამოიცნობს ჰოსტის საათის 0-დან 1-ზე ასვლას[cite: 1]
    wire       load_start    = uio_in[3] & ~uio3_d; // ამოიცნობს ჩატვირთვის დაწყების სიგნალს[cite: 1]
    wire [7:0] cfg_byte      = {cfg_shift[6:0], uio_in[0]}; // კრავს 8-ბიტიან კონფიგურაციის ბაიტს[cite: 1]
    // როდის უნდა ჩაიწეროს ინსტრუქცია მეხსიერებაში[cite: 1]
    wire imem_write_enable = !load_start && uio_in[3] && host_clk_rise && 
                             !uio_in[2] && (load_bit == 4'd15); 

    // ინსტრუქციების მეხსიერების მოდულის (რომელიც კოდის ბოლოშია აღწერილი) გამოძახება[cite: 1]
    protocol_instruction_memory instruction_memory (
        .clk(clk),
        .rst_n(rst_n),
        .write_enable(imem_write_enable),
        .write_address(load_addr),
        .write_data({load_shift[14:0], uio_in[0]}),
        .read_address(pc), // კითხულობს მიმდინარე PC-დან (Program Counter)[cite: 1]
        .read_data(imem_read_data)
    );

    // ეს ბლოკი იჭერს ჰოსტის საათის და სიგნალების კიდეებს (Edge detection)[cite: 1]
    always @(posedge clk or negedge rst_n) begin : host_edge_capture 
        if (!rst_n) begin // თუ რესეტია (0)[cite: 1]
            host_clk_d <= 1'b0; // ყველაფერს ანულებს[cite: 1]
            uio3_d     <= 1'b0;
        end else begin // სხვა შემთხვევაში (საათის ყოველ ტიკზე)[cite: 1]
            host_clk_d <= uio_in[1]; // ინახავს წინა მნიშვნელობებს[cite: 1]
            uio3_d     <= uio_in[3];
        end
    end

    // ინსტრუქციის (16-ბიტიანი) დანაწევრება ლოგიკურ ნაწილებად[cite: 1]
    wire [3:0] opcode    = instr[15:12]; // ინსტრუქციის კოდი (ოპერაცია, მაგ. JMP, WAIT) - უფროსი 4 ბიტი[cite: 1]
    wire [3:0] operand   = instr[11:8];  // ოპერანდი - რაზე სრულდება ოპერაცია[cite: 1]
    wire [3:0] side_set  = instr[7:4];   // გვერდითი პინების კონტროლის ბიტები[cite: 1]
    wire [3:0] delay_imm = instr[3:0];   // დაყოვნების მნიშვნელობა ინსტრუქციის ბოლოს[cite: 1]
    wire [4:0] jump_tgt  = {operand[3], side_set}; // გადახტომის (Jump) მისამართი[cite: 1]

    // ინსტრუქციების კოდები (Opcodes), რომლებსაც ეს პროცესორი იგებს[cite: 1]
    localparam OP_NOP    = 4'h0; // არაფერი გააკეთო (No Operation)[cite: 1]
    localparam OP_JMP    = 4'h1; // გადახტი სხვა მისამართზე (Jump)[cite: 1]
    localparam OP_WAIT   = 4'h2; // დაელოდე სიგნალს (Wait)[cite: 1]
    localparam OP_IN     = 4'h3; // წაიკითხე შემავალი პინიდან (In)[cite: 1]
    localparam OP_OUT    = 4'h4; // გააგზავნე გამომავალ პინზე (Out)[cite: 1]
    localparam OP_PUSH   = 4'h5; // ჩააგდე მიღებული მონაცემი RX FIFO-ში (Push)[cite: 1]
    localparam OP_PULL   = 4'h6; // ამოიღე მონაცემი TX FIFO-დან OSR-ში (Pull)[cite: 1]
    localparam OP_MOV    = 4'h7; // გადაიტანე მონაცემი ერთი ადგილიდან მეორეში (Move)[cite: 1]
    localparam OP_SET    = 4'h8; // დააყენე რეგისტრის ან პინის მნიშვნელობა (Set)[cite: 1]
    localparam OP_IRQ    = 4'h9; // გამოიძახე წყვეტა (Interrupt Request)[cite: 1]
    localparam OP_DELAY  = 4'hA; // დაელოდე გარკვეული დრო (Delay)[cite: 1]
    localparam OP_TOGGLE = 4'hB; // შეცვალე პინის მდგომარეობა საპირისპიროთი (0->1 ან 1->0)[cite: 1]
    localparam OP_SAMPLE = 4'hC; // აიღე ნიმუში პინებიდან (Sample)[cite: 1]
    localparam OP_HALT   = 4'hF; // გააჩერე მუშაობა (Halt)[cite: 1]

    // ლოდინის (Wait) ინსტრუქციის ლოგიკა სიგნალის ცვლილებაზე (Edge)[cite: 1]
    wire [7:0] wait_rise_event = protocol_in & ~pin_in_prev; // იგებს სად მოხდა 0->1 ცვლილება[cite: 1]
    wire [7:0] wait_fall_event = ~protocol_in & pin_in_prev; // იგებს სად მოხდა 1->0 ცვლილება[cite: 1]
    // ამოწმებს, არის თუ არა ახლა WAIT ინსტრუქციის შესრულების დრო[cite: 1]
    wire wait_edge_cycle = !uio_in[3] && !load_mode && tick && 
                           state == S_EXEC && opcode == OP_WAIT; 
    // ნიღბები, რომ წავშალოთ დამუშავებული ლოდინის მოვლენები[cite: 1]
    wire [7:0] wait_rise_clear_mask = 
        (wait_edge_cycle && side_set[0] && operand[0] && 
         wait_rise_pending[operand[3:1]]) ? (8'b1 << operand[3:1]) : 8'b0;
    wire [7:0] wait_fall_clear_mask = 
        (wait_edge_cycle && side_set[0] && !operand[0] && 
         wait_fall_pending[operand[3:1]]) ? (8'b1 << operand[3:1]) : 8'b0;
         
    // როდის ხდება FIFO-ებიდან ამოღება/ჩადება[cite: 1]
    wire tx_dequeue = tick && (state == S_EXEC) && 
                      ((opcode == OP_OUT && autopull_hit) || 
                       (opcode == OP_PULL && !tx_empty));
    wire tx_enqueue = host_write_req && ((tx_count != 4'd8) || tx_dequeue);
    wire rx_enqueue = tick && (state == S_EXEC) && 
                      ((opcode == OP_PUSH && (!rx_full || rx_dequeue)) || 
                       autopush_hit);
    wire rx_fifo_write_enable = !uio_in[3] && !load_mode && tick && 
                                (state == S_EXEC) && 
                                ((opcode == OP_PUSH && (!rx_full || rx_dequeue)) || 
                                 autopush_hit);
    wire [7:0] rx_fifo_write_data = autopush_hit ? 
                                    {isr[6:0], protocol_in[operand[2:0]]} : isr[7:0];

    // FIFO მეხსიერების მოდულის გამოძახება[cite: 1]
    protocol_fifo_storage fifo_storage (
        .clk(clk),
        .rst_n(rst_n),
        .tx_write_enable(tx_enqueue),
        .tx_write_address(tx_wr[2:0]),
        .tx_write_data(ui_in),
        .tx_read_address(tx_rd[2:0]),
        .tx_read_data(tx_fifo_data),
        .rx_write_enable(rx_fifo_write_enable),
        .rx_write_address(rx_wr[2:0]),
        .rx_write_data(rx_fifo_write_data),
        .rx_read_address(rx_rd[2:0]),
        .rx_read_data(rx_fifo_data)
    );

    reg [4:0] pc_target; // სად უნდა წავიდეს შემდეგ ინსტრუქციაზე (Target PC)[cite: 1]
    reg [7:0] next_pin_out; // რა უნდა გავიდეს პინებზე შემდეგ ეტაპზე[cite: 1]

    // მთავარი ბლოკი - ინსტრუქციების ჩატვირთვა და შესრულება (State Machine)[cite: 1]
    always @(posedge clk or negedge rst_n) begin : loader_and_execution_fsm 
        if (!rst_n) begin // რესეტის დროს ყველაფრის განულება (საწყის მდგომარეობაში დაბრუნება)[cite: 1]
            pc <= 5'd0; instr <= 16'h0000;
            osr <= 32'h0; isr <= 32'h0;
            osr_count <= 5'd0; isr_count <= 5'd0;
            x_reg <= 8'h0; y_reg <= 8'h0;
            pin_out <= 8'h0; pin_oe <= 8'h0;
            delay_cnt <= 16'h0; state <= S_FETCH; next_state <= S_FETCH;
            irq_pending <= 1'b0;
            pin_in_prev <= 8'h00;
            wait_rise_pending <= 8'h00;
            wait_fall_pending <= 8'h00;
            tx_rd <= 4'd0;
            rx_wr <= 4'd0;
            load_shift <= 16'h0; cfg_shift <= 8'h0;
            load_bit <= 4'd0; cfg_bit <= 3'd0;
            load_addr <= 5'd0; load_mode <= 1'b0;
            cfg_clkdiv_int <= 16'd0; cfg_clkdiv_frac <= 8'd0;
            cfg_wrap_top <= 5'd31; cfg_wrap_bottom <= 5'd0;
            cfg_shift_dir <= 2'd0;
            cfg_autopull <= 1'b0; cfg_autopush <= 1'b0;
            cfg_pull_thresh <= 5'd0; cfg_push_thresh <= 5'd31;
            cfg_side_count <= 4'd0;
            cfg_side_oe <= 1'b0;
        end else begin // ნორმალური მუშაობის რეჟიმი ყოველ კლოკზე[cite: 1]
            pin_in_prev <= protocol_in; // იმახსოვრებს მიმდინარე პინებს შემდეგისთვის[cite: 1]
            
            // ლოდინის (Wait) მოვლენების განახლება[cite: 1]
            if (uio_in[3] || load_mode) begin
                wait_rise_pending <= 8'h00;
                wait_fall_pending <= 8'h00;
            end else begin
                wait_rise_pending <= (wait_rise_pending & ~wait_rise_clear_mask) | 
                                     wait_rise_event;
                wait_fall_pending <= (wait_fall_pending & ~wait_fall_clear_mask) | 
                                     wait_fall_event;
            end

            // ჩატვირთვის რეჟიმის (Load mode) მართვა, როცა ჰოსტი გვიგზავნის ახალ კოდს/კონფიგურაციას[cite: 1]
            if (load_start) begin
                load_mode  <= 1'b1; // გადადის ჩატვირთვის რეჟიმში[cite: 1]
                load_addr  <= 5'd0; // იწყებს მე-0 მისამართიდან[cite: 1]
                load_bit   <= 4'd0;
                cfg_bit    <= 3'd0;
                load_shift <= 16'h0;
                cfg_shift  <= 8'h0;
            end else if (uio_in[3]) begin
                load_mode <= 1'b1;
                if (host_clk_rise) begin // როცა ჰოსტის კლოკი ადის ზემოთ[cite: 1]
                    if (uio_in[2] == 1'b0) begin // თუ uio_in[2] არის 0, იტვირთება ინსტრუქციები[cite: 1]
                        load_shift <= {load_shift[14:0], uio_in[0]}; // კრავს ბიტებს სათითაოდ[cite: 1]
                        if (load_bit == 4'd15) begin // როცა 16 ბიტი შეიკრიბება[cite: 1]
                            load_bit  <= 4'd0; // ანულებს ბიტის მრიცხველს[cite: 1]
                            load_addr <= load_addr + 1'b1; // გადადის შემდეგ მისამართზე[cite: 1]
                        end else begin
                            load_bit <= load_bit + 1'b1;
                        end
                    end else begin // თუ uio_in[2] არის 1, იტვირთება კონფიგურაცია[cite: 1]
                        cfg_shift <= cfg_byte[6:0];
                        if (cfg_bit == 3'd7) begin // როცა 8 ბიტი (ბაიტი) შეიკრიბება[cite: 1]
                            // ანაწილებს ამ 1 ბაიტს შესაბამის კონფიგურაციის რეგისტრში მისამართის მიხედვით[cite: 1]
                            case (load_addr)
                                5'd0:  cfg_clkdiv_int[7:0]  <= cfg_byte;
                                5'd1:  cfg_clkdiv_int[15:8] <= cfg_byte;
                                5'd2:  cfg_clkdiv_frac      <= cfg_byte;
                                5'd3:  cfg_wrap_top         <= cfg_byte[4:0];
                                5'd4:  cfg_wrap_bottom      <= cfg_byte[4:0];
                                5'd5:  cfg_shift_dir        <= cfg_byte[1:0];
                                5'd6:  cfg_autopull         <= cfg_byte[0];
                                5'd7:  cfg_autopush         <= cfg_byte[0];
                                5'd8:  cfg_pull_thresh      <= cfg_byte[4:0];
                                5'd9:  cfg_push_thresh      <= cfg_byte[4:0];
                                5'd10: cfg_side_count       <= cfg_byte[3:0];
                                5'd11: cfg_side_oe          <= cfg_byte[0];
                                default: ;
                            endcase
                            cfg_bit   <= 3'd0;
                            load_addr <= load_addr + 1'b1;
                        end else begin
                            cfg_bit <= cfg_bit + 1'b1;
                        end
                    end
                end
            end else if (load_mode) begin // ჩატვირთვა დასრულდა[cite: 1]
                load_mode  <= 1'b0; // გამოვდივართ ჩატვირთვის რეჟიმიდან[cite: 1]
                pc         <= 5'd0; // ვიწყებთ მე-0 ინსტრუქციიდან[cite: 1]
                state      <= S_FETCH; // გადავდივართ FETCH (ინსტრუქციის წაკითხვის) მდგომარეობაში[cite: 1]
                next_state <= S_FETCH;
                osr_count  <= 5'd0;
                isr_count  <= 5'd0;
            end

            // თუ ჩატვირთვის რეჟიმში არ ვართ და მოვიდა "ტიკი" (სამუშაო კლოკი)[cite: 1]
            if (!uio_in[3] && !load_mode && tick) begin
                case (state)
                    S_FETCH: begin // ინსტრუქციის მოტანის ეტაპი[cite: 1]
                        instr <= imem_read_data; // იღებს ინსტრუქციას მეხსიერებიდან[cite: 1]
                        state <= S_EXEC; // გადადის შესრულების ეტაპზე[cite: 1]
                    end

                    S_EXEC: begin // ინსტრუქციის შესრულების ეტაპი[cite: 1]
                        pc_target = pc; // ნაგულისხმევად ვრჩებით იმავე ინსტრუქციაზე[cite: 1]
                        next_pin_out = pin_out; // ნაგულისხმევად პინები არ იცვლება[cite: 1]

                        // გვერდითი პინების (Side-set) ლოგიკის შესრულება (თუ გამოიყენება)[cite: 1]
                        if (side_mask != 4'b0000 && 
                            opcode != OP_SET && opcode != OP_TOGGLE && 
                            opcode != OP_WAIT) begin
                            if (cfg_side_oe)
                                pin_oe[3:0] <= (pin_oe[3:0] & ~side_mask) | 
                                               (side_set & side_mask);
                            else
                                next_pin_out[3:0] = 
                                    (next_pin_out[3:0] & ~side_mask) | 
                                    (side_set & side_mask);
                        end

                        next_state = S_FETCH; // ნაგულისხმევად შემდეგი ეტაპია ახალი ინსტრუქციის მოტანა[cite: 1]

                        // არკვევს, რომელი ინსტრუქცია უნდა შეასრულოს[cite: 1]
                        case (opcode)
                            OP_NOP: pc_target = pc + 1'b1; // NOP: არაფერს აკეთებს, უბრალოდ გადადის შემდეგ ინსტრუქციაზე (PC+1)[cite: 1]

                            OP_JMP: begin // JMP: გადახტომა პირობების მიხედვით[cite: 1]
                                case (operand[2:0])
                                    3'b100: begin // გადახტი თუ X არ არის 0 და შეამცირე X[cite: 1]
                                        if (x_reg != 8'h0) begin
                                            x_reg <= x_reg - 1'b1;
                                            pc_target = jump_tgt;
                                        end else pc_target = pc + 1'b1;
                                    end
                                    3'b101: begin // გადახტი თუ Y არ არის 0 და შეამცირე Y[cite: 1]
                                        if (y_reg != 8'h0) begin
                                            y_reg <= y_reg - 1'b1;
                                            pc_target = jump_tgt;
                                        end else pc_target = pc + 1'b1;
                                    end
                                    3'b110: begin // გადახტი თუ X არის 0[cite: 1]
                                        if (x_reg == 8'h0) pc_target = jump_tgt;
                                        else pc_target = pc + 1'b1;
                                    end
                                    3'b111: begin // გადახტი თუ Y არის 0[cite: 1]
                                        if (y_reg == 8'h0) pc_target = jump_tgt;
                                        else pc_target = pc + 1'b1;
                                    end
                                    default: pc_target = jump_tgt; // უპირობო გადახტომა[cite: 1]
                                endcase
                            end

                            OP_WAIT: begin // WAIT: დაელოდე პინის ცვლილებას[cite: 1]
                                // ამოწმებს დადგა თუ არა ლოდინის პირობა[cite: 1]
                                if ((!side_set[0] && 
                                     protocol_in[operand[3:1]] == operand[0]) || 
                                    (side_set[0] && operand[0] && 
                                     wait_rise_pending[operand[3:1]]) || 
                                    (side_set[0] && !operand[0] && 
                                     wait_fall_pending[operand[3:1]]))
                                    pc_target = pc + 1'b1; // თუ დადგა, გადადის შემდეგზე[cite: 1]
                                else
                                    next_state = S_EXEC; // თუ არა, რჩება ისევ შესრულების რეჟიმში (ელოდება)[cite: 1]
                            end

                            OP_IN: begin // IN: შემოიტანე მონაცემი პინიდან ISR-ში[cite: 1]
                                isr <= {isr[30:0], protocol_in[operand[2:0]]}; // ამატებს ბიტს მარჯვნიდან[cite: 1]
                                isr_count <= isr_count + 1'b1; // ზრდის მრიცხველს[cite: 1]
                                pc_target = pc + 1'b1;
                            end

                            OP_OUT: begin // OUT: გაიტანე მონაცემი OSR-დან პინებზე[cite: 1]
                                if (operand[3]) begin
                                    next_pin_out[operand[2:0]] = 1'b0;
                                    pin_oe[operand[2:0]] <= ~out_bit;
                                end else begin
                                    next_pin_out[operand[2:0]] = out_bit; // გააქვს ბიტი პინზე[cite: 1]
                                end
                                // აჩოჩებს (Shift) OSR-ს მიმართულების მიხედვით[cite: 1]
                                if (cfg_shift_dir == 2'd0) osr <= {1'b0, osr_eff[31:1]};
                                else                       osr <= {osr_eff[30:0], 1'b0};
                                if (osr_count_eff > 5'd0)
                                    osr_count <= osr_count_eff - 1'b1; // ამცირებს დარჩენილი ბიტების რაოდენობას[cite: 1]
                                if (autopull_hit) begin // თუ ავტომატური ამოღება ჩაირთო[cite: 1]
                                    tx_rd    <= tx_rd + 1'b1; // წაიკითხე შემდეგი მონაცემი FIFO-დან[cite: 1]
                                end
                                pc_target = pc + 1'b1;
                            end

                            OP_PUSH: begin // PUSH: ISR-ის მნიშვნელობის ჩაგდება RX FIFO-ში[cite: 1]
                                if (!rx_full || rx_dequeue) begin // თუ ადგილი არის[cite: 1]
                                    rx_wr <= rx_wr + 1'b1; // ვწერთ FIFO-ში[cite: 1]
                                    isr_count <= 5'd0; // ვანულებთ ISR-ის მრიცხველს[cite: 1]
                                    pc_target = pc + 1'b1;
                                end else next_state = S_EXEC; // თუ ადგილი არაა, ველოდებით (ბლოკირება)[cite: 1]
                            end

                            OP_PULL: begin // PULL: მონაცემის ამოღება TX FIFO-დან OSR-ში[cite: 1]
                                if (!tx_empty) begin // თუ ცარიელი არაა[cite: 1]
                                    osr <= tx_fifo_word; // ვიწერთ OSR-ში[cite: 1]
                                    tx_rd <= tx_rd + 1'b1; // ვწევთ FIFO-ს მრიცხველს[cite: 1]
                                    osr_count <= 5'd8; // ვაყენებთ 8 ბიტზე[cite: 1]
                                    pc_target = pc + 1'b1;
                                end else next_state = S_EXEC; // თუ ცარიელია, ველოდებით[cite: 1]
                            end

                            OP_MOV: begin // MOV: მონაცემის კოპირება[cite: 1]
                                case (operand[2:0]) // საიდან სად მიდის[cite: 1]
                                    3'h0: osr <= cfg_shift_dir == 2'd0 ? 
                                                  {24'b0, x_reg} : {x_reg, 24'b0}; // X-დან OSR-ში[cite: 1]
                                    3'h1: x_reg <= osr[7:0]; // OSR-დან X-ში[cite: 1]
                                    3'h2: osr <= cfg_shift_dir == 2'd0 ? 
                                                  {24'b0, y_reg} : {y_reg, 24'b0}; // Y-დან OSR-ში[cite: 1]
                                    3'h3: y_reg <= osr[7:0]; // OSR-დან Y-ში[cite: 1]
                                    3'h4: isr <= {24'b0, protocol_in}; // პინებიდან ISR-ში[cite: 1]
                                    3'h5: next_pin_out = isr[7:0]; // ISR-დან პინებზე[cite: 1]
                                    3'h6: next_pin_out = x_reg; // X-დან პინებზე[cite: 1]
                                    3'h7: next_pin_out = y_reg; // Y-დან პინებზე[cite: 1]
                                    default: ;
                                endcase
                                pc_target = pc + 1'b1;
                            end

                            OP_SET: begin // SET: მნიშვნელობების დაყენება[cite: 1]
                                case (operand[2:0])
                                    3'h0: next_pin_out[3:0] = side_set; // ქვედა 4 პინის დაყენება[cite: 1]
                                    3'h1: x_reg <= {4'b0, side_set}; // X-ის დაყენება[cite: 1]
                                    3'h2: y_reg <= {4'b0, side_set}; // Y-ის დაყენება[cite: 1]
                                    3'h3: pin_oe <= {4'b0, side_set}; // პინების მიმართულების დაყენება[cite: 1]
                                    3'h4: next_pin_out[7:4] = side_set; // ზედა 4 პინის დაყენება[cite: 1]
                                    default: ;
                                endcase
                                pc_target = pc + 1'b1;
                            end

                            OP_IRQ: begin // IRQ: წყვეტის მოთხოვნა (Interrupt)[cite: 1]
                                irq_pending <= 1'b1;
                                pc_target = pc + 1'b1;
                            end

                            OP_DELAY: begin // DELAY: დაყოვნება დროში (რეგისტრებით)[cite: 1]
                                if ({x_reg, y_reg} == 16'h0) begin // თუ დრო 0-ია, გავდივართ[cite: 1]
                                    pc_target = pc + 1'b1;
                                end else begin
                                    delay_cnt  <= {x_reg, y_reg}; // ვწერთ X და Y-ს დაყოვნების მრიცხველში[cite: 1]
                                    pc_target  = pc + 1'b1;
                                    next_state = S_DELAY; // გადავდივართ დაყოვნების მდგომარეობაში[cite: 1]
                                end
                            end

                            OP_TOGGLE: begin // TOGGLE: პინების ინვერსია (Invert)[cite: 1]
                                next_pin_out[3:0] = next_pin_out[3:0] ^ side_set; // ^ არის XOR ოპერაცია[cite: 1]
                                pc_target = pc + 1'b1;
                            end

                            OP_SAMPLE: begin // SAMPLE: შემომავალი პინების მდგომარეობის აღება[cite: 1]
                                isr <= {24'b0, protocol_in};
                                isr_count <= 5'd8;
                                pc_target = pc + 1'b1;
                            end

                            OP_HALT: next_state = S_EXEC; // HALT: გაჩერება (რჩება იგივე ინსტრუქციაზე და არ გადადის შემდეგზე)[cite: 1]

                            default: pc_target = pc + 1'b1; // უცნობი ინსტრუქციის შემთხვევაში გადადის შემდეგზე[cite: 1]
                        endcase

                        // ციკლის (Wrap) ლოგიკა. თუ მივაღწიეთ ბოლოს, გადავდივართ დასაწყისში[cite: 1]
                        if (cfg_wrap_top >= cfg_wrap_bottom && pc_target > cfg_wrap_top)
                            pc <= cfg_wrap_bottom; // ვბრუნდებით ქვედა საზღვარზე[cite: 1]
                        else
                            pc <= pc_target; // მივდივართ გამოთვლილ მისამართზე[cite: 1]

                        pin_out <= next_pin_out; // ვაახლებთ პინებს[cite: 1]

                        // Autopush (ავტომატური ჩაგდება FIFO-ში)[cite: 1]
                        if (autopush_hit) begin
                            rx_wr <= rx_wr + 1'b1;
                            isr_count <= 5'd0;
                        end

                        // თუ ინსტრუქციას ბოლოში აქვს დაყოვნების მნიშვნელობა (Delay Imm)[cite: 1]
                        if (delay_imm != 4'd0 && next_state == S_FETCH) begin
                            delay_cnt  <= {12'b0, delay_imm}; // ვწერთ ამ მნიშვნელობას[cite: 1]
                            next_state = S_DELAY; // გადავდივართ დაყოვნების რეჟიმში[cite: 1]
                        end

                        if (next_state != S_EXEC) // მდგომარეობის განახლება[cite: 1]
                            state <= next_state;
                    end

                    S_DELAY: begin // დაყოვნების ეტაპი[cite: 1]
                        if (delay_cnt == 16'd0) state <= S_FETCH; // თუ დრო ამოიწურა, გადავდივართ შემდეგ ინსტრუქციაზე[cite: 1]
                        else                    delay_cnt <= delay_cnt - 1'b1; // თუ არა, ვაკლებთ 1 ტიკს[cite: 1]
                    end

                    default: state <= S_FETCH; // გაუთვალისწინებელი მდგომარეობისას დაბრუნება დასაწყისში[cite: 1]
                endcase
            end
        end
    end

    // ჰოსტთან მონაცემთა გაცვლის ლოგიკა[cite: 1]
    always @(posedge clk or negedge rst_n) begin : host_fifo_transfer 
        if (!rst_n) begin
            tx_wr <= 4'd0;
            rx_rd <= 4'd0;
            host_fifo_data <= 8'h00;
        end else begin
            if (host_write_req && ((tx_count != 4'd8) || tx_dequeue)) begin // თუ ჰოსტს ჩაწერა უნდა და ადგილი არის[cite: 1]
                tx_wr <= tx_wr + 1'b1;
            end
            if (host_read_req && (rx_count != 4'd0)) begin // თუ ჰოსტს წაკითხვა უნდა და მონაცემი არის[cite: 1]
                host_fifo_data <= rx_fifo_data; // გადააქვს მონაცემი ჰოსტისკენ[cite: 1]
                rx_rd <= rx_rd + 1'b1;
            end
        end
    end

    // FIFO რიგებში ელემენტების რაოდენობის მთვლელი ლოგიკა[cite: 1]
    always @(posedge clk or negedge rst_n) begin : fifo_occupancy 
        if (!rst_n) begin
            tx_count <= 4'd0;
            rx_count <= 4'd0;
        end else begin
            case ({tx_enqueue, tx_dequeue}) // {ჩაგდება, ამოღება} კომბინაციები[cite: 1]
                2'b10: tx_count <= tx_count + 1'b1; // მხოლოდ ჩაგდება (ზრდის)[cite: 1]
                2'b01: tx_count <= tx_count - 1'b1; // მხოლოდ ამოღება (ამცირებს)[cite: 1]
                default: tx_count <= tx_count; // ორივე ან არცერთი (რჩება უცვლელი)[cite: 1]
            endcase
            case ({rx_enqueue, rx_dequeue}) // იგივე RX რიგისთვის[cite: 1]
                2'b10: rx_count <= rx_count + 1'b1;
                2'b01: rx_count <= rx_count - 1'b1;
                default: rx_count <= rx_count;
            endcase
        end
    end

    // საბოლოო გამომავალი პინების მინიჭება (Assign)[cite: 1]
    assign uo_out  = (host_fifo_mode && host_read_req) ? host_fifo_data : pin_out; // ან FIFO-ს მონაცემი გადის, ან პროცესორის პინები[cite: 1]
    assign uio_out = {pin_out[3:0], 4'b0000}; // uio გამომავალი პინები[cite: 1]
    assign uio_oe  = {pin_oe[3:0], 4'b0000}; // uio პინების მიმართულების სიგნალი[cite: 1]

    wire _unused = &{ena, 1'b0}; // გამაფრთხილებელი (Warning) მესიჯების ასარიდებლად გამოუყენებელ სიგნალებზე[cite: 1]

endmodule


// =========================================================================
// დამხმარე მოდული: საათის გამყოფი (Clock Divider)[cite: 1]
// ანელებს მთავარ clk სიგნალს და ქმნის იშვიათ tick სიგნალებს[cite: 1]
// =========================================================================
module protocol_clock_divider (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] cfg_clkdiv_int,  // მთელი ნაწილი[cite: 1]
    input  wire [7:0]  cfg_clkdiv_frac, // წილადი ნაწილი[cite: 1]
    output reg         tick
);

    reg [15:0] clkdiv_int_cnt;  // მთელი ნაწილის მთვლელი[cite: 1]
    reg [7:0] clkdiv_frac_acc;  // წილადი ნაწილის აკუმულატორი (შემგროვებელი)[cite: 1]
    wire [8:0] clkdiv_frac_sum = {1'b0, clkdiv_frac_acc} + 
                                  {1'b0, cfg_clkdiv_frac}; // ითვლის წილადების ჯამს[cite: 1]

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clkdiv_int_cnt  <= 16'd0;
            clkdiv_frac_acc <= 8'd0;
            tick            <= 1'b0;
        end else begin
            if (clkdiv_int_cnt == 16'd0) begin // როცა მრიცხველი ჩამოვა ნულზე[cite: 1]
                clkdiv_frac_acc <= clkdiv_frac_sum[7:0]; // ინახავს წილადის ნაშთს[cite: 1]
                if (cfg_clkdiv_int == 16'd0) // თუ გამყოფი ნულია (არ ვყოფთ)[cite: 1]
                    clkdiv_int_cnt <= 16'd0;
                else
                    // გადატვირთავს მრიცხველს და ამატებს 1-ს თუ წილადმა "გადაივსო" (გახდა > 1)[cite: 1]
                    clkdiv_int_cnt <= cfg_clkdiv_int - 1'b1 + 
                                      clkdiv_frac_sum[8]; 
                tick <= 1'b1; // ქმნის 1 ტიკს (პულსს)[cite: 1]
            end else begin
                clkdiv_int_cnt <= clkdiv_int_cnt - 1'b1; // მრიცხველის შემცირება[cite: 1]
                tick           <= 1'b0; // ტიკი გამორთულია[cite: 1]
            end
        end
    end
endmodule


// =========================================================================
// დამხმარე მოდული: ინსტრუქციების მეხსიერება[cite: 1]
// ინახავს 32 ცალ 16-ბიტიან ინსტრუქციას[cite: 1]
// =========================================================================
module protocol_instruction_memory (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        write_enable,   // ჩაწერის ნებართვა[cite: 1]
    input  wire [4:0]  write_address,  // სად ჩაწეროს[cite: 1]
    input  wire [15:0] write_data,     // რა ჩაწეროს[cite: 1]
    input  wire [4:0]  read_address,   // საიდან წაიკითხოს[cite: 1]
    output wire [15:0] read_data       // წაკითხული მონაცემი[cite: 1]
);

    reg [15:0] words [0:31]; // თვითონ მეხსიერების მასივი: 32 უჯრა, თითო 16 ბიტიანი[cite: 1]
    reg [31:0] word_valid;   // 32-ბიტიანი ველი, რომელიც აღნიშნავს რომელ უჯრაში წერია ნამდვილი მონაცემი[cite: 1]

    // ჩაწერის დაქონტურების ბლოკი[cite: 1]
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            word_valid <= 32'b0; // თავიდან ყველაფერი არავალიდურია[cite: 1]
        end else if (write_enable) begin
            word_valid[write_address] <= 1'b1; // ჩაწერისას უჯრას მონიშნავს ვალიდურად[cite: 1]
        end
    end

    // მეხსიერებაში ჩაწერის ბლოკი[cite: 1]
    always @(posedge clk) begin
        if (rst_n && write_enable)
            words[write_address] <= write_data; // წერს მონაცემს[cite: 1]
    end

    // წაკითხვის ოპერაცია. თუ უჯრა არაა ვალიდური, აბრუნებს 16'hF000 (რაც არის HALT ინსტრუქცია)[cite: 1]
    assign read_data = word_valid[read_address] ? words[read_address] : 16'hF000; 
endmodule


// =========================================================================
// დამხმარე მოდული: FIFO (First-In, First-Out) მეხსიერება[cite: 1]
// გამოიყენება მონაცემების დროებით შესანახად ჰოსტსა და პროცესორს შორის რიგში[cite: 1]
// =========================================================================
module protocol_fifo_storage (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_write_enable,
    input  wire [2:0] tx_write_address,
    input  wire [7:0] tx_write_data,
    input  wire [2:0] tx_read_address,
    output wire [7:0] tx_read_data,
    input  wire       rx_write_enable,
    input  wire [2:0] rx_write_address,
    input  wire [7:0] rx_write_data,
    input  wire [2:0] rx_read_address,
    output wire [7:0] rx_read_data
);

    reg [7:0] tx_fifo [0:7]; // გამოსაგზავნი (TX) მონაცემების მასივი: 8 უჯრა თითო 8 ბიტიანი[cite: 1]
    reg [7:0] rx_fifo [0:7]; // მისაღები (RX) მონაცემების მასივი: 8 უჯრა თითო 8 ბიტიანი[cite: 1]

    always @(posedge clk) begin
        if (rst_n) begin
            if (tx_write_enable)
                tx_fifo[tx_write_address] <= tx_write_data; // TX-ში ჩაწერა[cite: 1]
            if (rx_write_enable)
                rx_fifo[rx_write_address] <= rx_write_data; // RX-ში ჩაწერა[cite: 1]
        end
    end

    assign tx_read_data = tx_fifo[tx_read_address]; // TX-დან წაკითხვა[cite: 1]
    assign rx_read_data = rx_fifo[rx_read_address]; // RX-დან წაკითხვა[cite: 1]
endmodule

// აბრუნებს ნაგულისხმევ წესებს.[cite: 1]
`default_nettype wire
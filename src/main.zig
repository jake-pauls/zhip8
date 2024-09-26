const std = @import("std");
const sdl = @import("zsdl2");

const core = @import("core.zig");

pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Initialize the hardware
    var hardware = core.Hardware{};

    // Read a ROM from disk for loading into the emulator
    // NOTE: Program should be loaded into memory at address 0x200
    const rom_file_path = "data/ROM/IBM Logo.ch8";
    // const rom_file_path = "data/ROM/Test/test_opcode.ch8";
    const read_buffer: []u8 = try std.fs.cwd().readFileAlloc(allocator, rom_file_path, std.math.maxInt(u32));
    defer allocator.free(read_buffer);
    for (0..read_buffer.len) |i| {
        hardware.memory[0x200 + i] = read_buffer[i];
    }

    // Load the system font into memory
    for (0..core.system_font.len) |i| {
        hardware.memory[0x050 + i] = core.system_font[i];
    }

    // SDL
    try sdl.init(.{ .audio = true, .video = true });
    defer sdl.quit();

    const window = try sdl.Window.create(
        "ZHIP8",
        sdl.Window.pos_undefined,
        sdl.Window.pos_undefined,
        256, //core.display_width_in_pixels * 4
        128, //core.display_height_in_pixels * 4
        .{ .opengl = true, .allow_highdpi = true },
    );
    defer window.destroy();

    const renderer = try sdl.createRenderer(window, -1, sdl.Renderer.Flags{});
    try sdl.setRenderDrawColor(renderer, sdl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
    try sdl.renderClear(renderer);

    var running = true;
    while (running) {
        var event: sdl.Event = undefined;
        while (sdl.pollEvent(&event)) {
            switch (event.type) {
                sdl.EventType.quit => running = false,
                else => {},
            }
        }

        const op = fetch(&hardware);
        execute(&hardware, &op);

        if (is_draw_op(&op)) {
            try sdl_draw(&hardware, renderer);
        }
    }
}

//
// SDL
//

/// Uses the SDL renderer to draw pixels stored in the CHIP-8's display register to the screen.
fn sdl_draw(hardware: *core.Hardware, renderer: *sdl.Renderer) !void {
    // Clear the screen
    try sdl.setRenderDrawColor(renderer, core.sdl_color_black);
    try sdl.renderClear(renderer);

    // Draw pixels from the display
    try sdl.setRenderDrawColor(renderer, core.sdl_color_white);
    for (0..core.display_height_in_pixels) |y| {
        for (0..core.display_width_in_pixels) |x| {
            const pixel: u1 = hardware.display[y][x];
            if (pixel == 1) {
                // TODO: Appropriately upscale the screen, however, it's nice to see this for debugging purposes at the moment
                try sdl.renderDrawPoint(renderer, @intCast(x * 4), @intCast(y * 4));
            }
        }
    }

    sdl.renderPresent(renderer);
}

//
// Emulator
//

/// Fetches the next instruction from memory. In the CHIP-8 specification, one instruction is
/// represented with 16 bytes, requiring two slots in memory each. As a result, when fetching
/// instructions we fetch the one currently indiciated by the program counter as well as the next,
/// and increment the program counter by two.
fn fetch(hardware: *core.Hardware) core.Opcode {
    const upper_instruction_bits = hardware.memory[hardware.PC];
    const lower_instruction_bits = hardware.memory[hardware.PC + 1];
    hardware.PC += 2;

    // Create a 16-bit integer from both 8-bit ints.
    // ----------------------------------------------------
    // 1001 0010 - A2
    // 0101 0111 - 57
    // ----------------------------------------------------
    // 0000 0000 0101 0111 - lower_bits
    // 1001 0010 0000 0000 - upper_bits << 8
    // 1001 0010 0101 0111 - lower_bits | (upper_bits << 8)

    const value: u16 = lower_instruction_bits | @as(u16, upper_instruction_bits) << 8;

    // Create a 4-bit integer from 8-bit ints.
    // ----------------------------------------------------
    // 1001 0010 - A2
    // ----------------------------------------------------
    // 1001 0010
    // 0000 1111 - 0x0F
    // 0000 0010 - lower

    const one = upper_instruction_bits >> 4;
    const two = upper_instruction_bits & 0x0F;

    // 1110 - 0x0E
    const three = lower_instruction_bits >> 4;
    const four = lower_instruction_bits & 0x0F;

    return core.Opcode{ .one = one, .two = two, .three = three, .four = four, .value = value };
}

/// Executes an instruction with the provided opcode on the current hardware state.
fn execute(hardware: *core.Hardware, op: *const core.Opcode) void {
    switch (op.one) {
        0x0 => {
            switch (op.two) {
                0x0 => {
                    switch (op.three) {
                        0xE => {
                            switch (op.four) {
                                0x0 => clear(hardware),
                                0xE => subroutine_return(hardware),
                                else => unreachable,
                            }
                        },
                        else => unreachable,
                    }
                },
                else => unreachable,
            }
        },
        0x1 => jump(hardware, op),
        0x2 => subroutine_call(hardware, op),
        0x6 => setVX(hardware, op),
        0x7 => addVX(hardware, op),
        0xA => setI(hardware, op),
        0xD => draw(hardware, op),
        else => unreachable,
    }
}

//
// Operations
//

/// Clears the screen.
///
/// Example:
///     00E0 - Clear the screen
fn clear(hardware: *core.Hardware) void {
    hardware.display = .{.{0} ** 64} ** 32;
}

/// Constructs the address of the jump using the last three bits of the opcode
/// and directly sets the program counter to the corresponding address.
///
/// Example:
///     1NNN - Jump to address NNN
///     1228 - Jump to address 0x228
fn jump(hardware: *core.Hardware, op: *const core.Opcode) void {
    const h: u12 = @as(u12, op.two) << 8;
    const t: u12 = @as(u12, op.three) << 4;
    const o: u12 = @as(u12, op.four);

    const address = h | t | o;
    hardware.PC = address;
}

/// Sets the value of the register indicated in the second bit of the opcode
/// to the value constructed by the last two bits of the opcode.
///
/// Example:
///     6XNN - Store the number NN in register VX
///     600C - Store the number 0x0C in register V0
fn setVX(hardware: *core.Hardware, op: *const core.Opcode) void {
    const register: u8 = op.two;
    const t: u8 = op.three << 4;
    const o: u8 = op.four;

    const value: u8 = t | o;
    hardware.V[register] = value;
}

/// Adds the value constructed by the last two bits of the opode to the
/// current value of the register indicated in the second bit of the opcode.
///
/// Example:
///     7XNN - Add the value NN to register VX
///     7008 - Add the value 0x08 to register VX
fn addVX(hardware: *core.Hardware, op: *const core.Opcode) void {
    const register: u8 = op.two;
    const t: u8 = op.three << 4;
    const o: u8 = op.four;

    const value: u8 = t | o;
    hardware.V[register] += value;
}

/// Sets the value of the index register (I) to the address constructed
/// from the last three bits of the opcode.
///
/// Example:
///     ANNN - Store memory address NNN in register I
///     A239 - Store memory address 0x239 in register I
fn setI(hardware: *core.Hardware, op: *const core.Opcode) void {
    const h: u12 = @as(u12, op.two) << 8;
    const t: u12 = @as(u12, op.three) << 4;
    const o: u12 = @as(u12, op.four);

    const address = h | t | o;
    hardware.I = address;
}

/// Calls the subroutine at the passed address by setting the PC
/// to it as well as pushing the current value PC onto the stack.
///
/// Example:
///     2NNN - Push the current address in the PC onto the stack and set the PC to address NNN as a subroutine call
///     22A5 - Push the current address in the PC onto the stack and set the PC to address 0x2A5 as a subroutine call
fn subroutine_call(hardware: *core.Hardware, op: *const core.Opcode) void {
    // Push the current address in the PC onto the stack}
    hardware.stack[hardware.stack_pointer] = hardware.PC;
    hardware.stack_pointer += 1;

    // Note: This is just a jump
    const h: u12 = @as(u12, op.two) << 8;
    const t: u12 = @as(u12, op.three) << 4;
    const o: u12 = @as(u12, op.four);

    const address = h | t | o;
    hardware.PC = address;
}

/// Returns from the current subroutine by popping an address off the stack
/// and setting the PC to it.
///
/// Example:
///     00EE - Pop an address from the stack and set the PC to it.
fn subroutine_return(hardware: *core.Hardware) void {
    // The stack pointer will always be looking one above the top of the stack
    hardware.PC = hardware.stack[hardware.stack_pointer - 1];
    // Decrementing the stack pointer is enough to consider the item popped, future entries will just overwrite this
    hardware.stack_pointer -= 1;
}

/// Draws a sprite at the position indicated by the values contained in the registers
/// of the second and third bits of the opcode with N bytes of data represented by the fourth
/// bit of the opcode starting at the address stored in I.
///
/// Example:
///     DXYN - Draw a sprite at position VX,VY with N bytes of data starting at the address stored in I
///     D01F - Draw a sprite at position V0,V1 with 0xF bytes of data starting at the address stored in I
fn draw(hardware: *core.Hardware, op: *const core.Opcode) void {
    const x = hardware.V[op.two] & 63;
    const y = hardware.V[op.three] & 31;
    const n = op.four;

    // Reset the flag register to 0 before drawing.
    // If any pixels are turned off by this draw operation the flag register should switch to 1.
    hardware.V[0xF] = 0;

    // Sprite data is defined in memory, with each register eight bits from the starting position
    //  e.g., one "opcode" is two lines @ 8 bits per line
    //
    // Example (IBM Logo):
    //  sprite for the "I" starts at 554 in memory and ends at 568

    for (0..n) |i| {
        const sprite_row: u8 = hardware.memory[hardware.I + i];

        // Maintain two indices, one for shifting and another for accessing screen pixels
        var shift_index: u3 = 7;
        var x_index: u3 = 0;

        // Iterate while the shifting index is positive, we break early to prevent underflow.
        while (shift_index >= 0 and x_index < 8) : (x_index += 1) {
            // Right shift the row by our shifting index and truncate it to
            // the last bit, this allows us to always access the end bit of the word
            const sprite_bit: u1 = @truncate(sprite_row >> shift_index);

            // XOR the bit on the screen to turn it off or on appropriately
            hardware.display[y + i][x + x_index] ^= sprite_bit;

            // The flag register should be turned on if a pixel was turned off during this draw.
            if (hardware.display[y + i][x + x_index] == 0 and sprite_bit == 1) {
                hardware.V[0xF] = 1;
            }

            if (shift_index == 0) {
                break;
            }
            shift_index -= 1;
        }
    }
}

//
// Utilities
//

fn is_draw_op(op: *const core.Opcode) bool {
    return op.one == 0x0 or op.one == 0xD;
}

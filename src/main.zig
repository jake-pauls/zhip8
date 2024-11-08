const std = @import("std");
const sdl = @import("zsdl2");

const core = @import("core.zig");

/// Configurable setting to set the register VX as VY prior to performing logical shifts.
/// Used in some CHIP-8 games and programs.
const set_vx_to_vy_on_shift: bool = false;
/// Configurable setting for the `jumpWithOffset` function that uses the second digit
/// in the opcode as the register (VX) to add to the address being provided.
const use_second_op_as_vx_for_jump_with_offset: bool = true;
/// Prints some logs that may help with debugging.
const print_info_logs: bool = false;

pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Initialize the hardware
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    var hardware = core.Hardware{ .randomizer = prng.random() };

    // Read a ROM from disk for loading into the emulator
    // NOTE: Program should be loaded into memory at address 0x200
    // const rom_file_path = "data/ROM/Tetris.ch8";
    // const rom_file_path = "data/ROM/Test/test_opcode.ch8";
    // const rom_file_path = "data/ROM/Test/bc_test.ch8";
    // const rom_file_path = "data/ROM/Test/SCTEST.ch8";
    const rom_file_path = "data/ROM/Test/chip8-test-suite/bin/4-flags.ch8";
    const read_buffer: []u8 = try std.fs.cwd().readFileAlloc(allocator, rom_file_path, std.math.maxInt(u32));
    defer allocator.free(read_buffer);
    for (0..read_buffer.len) |i| {
        hardware.memory[0x200 + i] = read_buffer[i];
    }

    // Initialize all values in the internal keyboard to 0
    // Decided to on using 0x0 to 0xF for this... because the memory here is unused anyways
    for (0..15) |i| {
        hardware.memory[0x0 + i] = 0;
    }

    // Load the system font into memory - common to use 0x050 to 0x09F
    for (0..core.system_font.len) |i| {
        hardware.memory[core.system_font_starting_address + i] = core.system_font[i];
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

    var isQuit = false;
    while (!isQuit) {
        sdlPollEvents(&hardware, &isQuit);

        const op = fetch(&hardware);
        if (print_info_logs) {
            std.log.info("next instruction: {X}\n", .{op.value});
        }

        execute(&hardware, &op);

        if (isDrawOp(&op)) {
            try sdlDraw(&hardware, renderer);
        }
    }
}

//
// SDL
//

/// Uses the SDL event pump to catch and respond to window events.
fn sdlPollEvents(hardware: *core.Hardware, isQuitEvent: *bool) void {
    var event: sdl.Event = undefined;

    // Reset flag for key presses
    hardware.was_key_pressed_this_frame = false;

    while (sdl.pollEvent(&event)) {
        switch (event.type) {
            sdl.EventType.quit => isQuitEvent.* = true,
            sdl.EventType.keydown => {
                switch (event.key.keysym.scancode) {
                    sdl.Scancode.@"1" => hardware.memory[0x0] = 1,
                    sdl.Scancode.@"2" => hardware.memory[0x1] = 1,
                    sdl.Scancode.@"3" => hardware.memory[0x2] = 1,
                    sdl.Scancode.@"4" => hardware.memory[0x3] = 1,
                    sdl.Scancode.q => hardware.memory[0x4] = 1,
                    sdl.Scancode.w => hardware.memory[0x5] = 1,
                    sdl.Scancode.e => hardware.memory[0x6] = 1,
                    sdl.Scancode.r => hardware.memory[0x7] = 1,
                    sdl.Scancode.a => hardware.memory[0x8] = 1,
                    sdl.Scancode.s => hardware.memory[0x9] = 1,
                    sdl.Scancode.d => hardware.memory[0xA] = 1,
                    sdl.Scancode.f => hardware.memory[0xB] = 1,
                    sdl.Scancode.z => hardware.memory[0xC] = 1,
                    sdl.Scancode.x => hardware.memory[0xD] = 1,
                    sdl.Scancode.c => hardware.memory[0xE] = 1,
                    sdl.Scancode.v => hardware.memory[0xF] = 1,
                    else => {},
                }
            },
            sdl.EventType.keyup => {
                switch (event.key.keysym.scancode) {
                    sdl.Scancode.@"1" => hardware.memory[0x0] = 0,
                    sdl.Scancode.@"2" => hardware.memory[0x1] = 0,
                    sdl.Scancode.@"3" => hardware.memory[0x2] = 0,
                    sdl.Scancode.@"4" => hardware.memory[0x3] = 0,
                    sdl.Scancode.q => hardware.memory[0x4] = 0,
                    sdl.Scancode.w => hardware.memory[0x5] = 0,
                    sdl.Scancode.e => hardware.memory[0x6] = 0,
                    sdl.Scancode.r => hardware.memory[0x7] = 0,
                    sdl.Scancode.a => hardware.memory[0x8] = 0,
                    sdl.Scancode.s => hardware.memory[0x9] = 0,
                    sdl.Scancode.d => hardware.memory[0xA] = 0,
                    sdl.Scancode.f => hardware.memory[0xB] = 0,
                    sdl.Scancode.z => hardware.memory[0xC] = 0,
                    sdl.Scancode.x => hardware.memory[0xD] = 0,
                    sdl.Scancode.c => hardware.memory[0xE] = 0,
                    sdl.Scancode.v => hardware.memory[0xF] = 0,
                    else => {},
                }
                // TODO: Refactor to only be performed for the keys supported by the CHIP-8
                hardware.was_key_pressed_this_frame = true;
            },
            else => {},
        }
    }
}

/// Uses the SDL renderer to draw pixels stored in the CHIP-8's display register to the screen.
fn sdlDraw(hardware: *core.Hardware, renderer: *sdl.Renderer) !void {
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
                                0xE => subroutineReturn(hardware),
                                else => unimplementedOpDump(op),
                            }
                        },
                        else => unimplementedOpDump(op),
                    }
                },
                else => unimplementedOpDump(op),
            }
        },
        0x1 => jump(hardware, op),
        0x2 => subroutineCall(hardware, op),
        0x3 => conditionalSkipEq(hardware, op),
        0x4 => conditionalSkipNeq(hardware, op),
        0x5 => conditionalSkipXYEq(hardware, op),
        0x6 => setVX(hardware, op),
        0x7 => addVX(hardware, op),
        0x8 => {
            switch (op.four) {
                0x0 => larSetVXVY(hardware, op),
                0x1 => larBitwiseOr(hardware, op),
                0x2 => larBitwiseAnd(hardware, op),
                0x3 => larBitwiseXor(hardware, op),
                0x4 => larAdd(hardware, op),
                0x5 => larSubtractVXVY(hardware, op),
                0x6 => larRightShift(hardware, op),
                0x7 => larSubtractVYVX(hardware, op),
                0xE => larLeftShift(hardware, op),
                else => unimplementedOpDump(op),
            }
        },
        0x9 => conditionalSkipXYNeq(hardware, op),
        0xA => setI(hardware, op),
        0xB => jumpWithOffset(hardware, op),
        0xC => larRandom(hardware, op),
        0xD => draw(hardware, op),
        0xE => {
            switch (op.three) {
                0x9 => {
                    switch (op.four) {
                        0xE => skipIfKeyPressed(hardware, op),
                        else => unimplementedOpDump(op),
                    }
                },
                0xA => {
                    switch (op.four) {
                        0x1 => skipIfKeyNotPressed(hardware, op),
                        else => unimplementedOpDump(op),
                    }
                },
                else => unimplementedOpDump(op),
            }
        },
        0xF => {
            switch (op.three) {
                0x0 => {
                    switch (op.four) {
                        0x7 => setVXToDelayTimer(hardware, op),
                        0xA => getKey(hardware),
                        else => unimplementedOpDump(op),
                    }
                },
                0x1 => {
                    switch (op.four) {
                        0x5 => setDelayTimerToVX(hardware, op),
                        0x8 => setSoundTimerToVX(hardware, op),
                        0xE => addVXToIndex(hardware, op),
                        else => unimplementedOpDump(op),
                    }
                },
                0x2 => {
                    switch (op.four) {
                        0x9 => fontCharacter(hardware, op),
                        else => unimplementedOpDump(op),
                    }
                },
                0x3 => {
                    switch (op.four) {
                        0x3 => binaryCodedDecimalConversion(hardware, op),
                        else => unimplementedOpDump(op),
                    }
                },
                0x5 => {
                    switch (op.four) {
                        0x5 => storeMemory(hardware, op),
                        else => unimplementedOpDump(op),
                    }
                },
                0x6 => {
                    switch (op.four) {
                        0x5 => loadMemory(hardware, op),
                        else => unimplementedOpDump(op),
                    }
                },
                else => unimplementedOpDump(op),
            }
        },
        else => unimplementedOpDump(op),
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
    hardware.display = .{.{0} ** core.display_width_in_pixels} ** core.display_height_in_pixels;
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

/// Jumps to the address NNN plus the value in register V0.
///
/// Configurable: Use `use_second_op_as_vx_for_jump_with_offset` to use the second opcode digit as the register to add to the base address.
///
/// Example:
///     BNNN - Jumps to the address NNN plus the value in register V0
///     B222 - Jumps to the address 222 plus the value in register V0 (333, if the value in register V0 is 111)
fn jumpWithOffset(hardware: *core.Hardware, op: *const core.Opcode) void {
    const h: u12 = @as(u12, op.two) << 8;
    const t: u12 = @as(u12, op.three) << 4;
    const o: u12 = @as(u12, op.four);

    var address: u12 = 0;
    if (use_second_op_as_vx_for_jump_with_offset) {
        address = (t | o) + hardware.V[op.two];
        hardware.PC = address;
    } else {
        address = (h | t | o) + hardware.V[0];
        hardware.PC = address;
    }
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
///     7008 - Add the value 0x08 to register V0
fn addVX(hardware: *core.Hardware, op: *const core.Opcode) void {
    const register: u8 = op.two;
    const t: u8 = op.three << 4;
    const o: u8 = op.four;

    const value: u8 = t | o;
    const ov = @addWithOverflow(hardware.V[register], value);

    hardware.V[register] = ov[0];
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
fn subroutineCall(hardware: *core.Hardware, op: *const core.Opcode) void {
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
///     00EE - Pop an address from the stack and set the PC to it
fn subroutineReturn(hardware: *core.Hardware) void {
    // The stack pointer will always be looking one above the top of the stack
    hardware.PC = hardware.stack[hardware.stack_pointer - 1];
    // Decrementing the stack pointer is enough to consider the item popped, future entries will just overwrite this
    hardware.stack_pointer -= 1;
}

/// Skips one two byte instruction if the value in VX is equal to the passed address.
///
/// Example:
///     3XNN - Skips one two byte instruction if the value in VX is equal to NN
///     30A0 - Skips one two byte instruction if the value in V0 is equal to 0xA0
fn conditionalSkipEq(hardware: *core.Hardware, op: *const core.Opcode) void {
    const t: u8 = @as(u8, op.three) << 4;
    const o: u8 = @as(u8, op.four);

    const value: u8 = t | o;

    // Skip the next two byte instruction if the value in VX is equal to NN
    if (hardware.V[op.two] == value) {
        hardware.PC += 2;
    }
}

/// Skips one two byte instruction if the value in VX is not equal to the passed address.
///
/// Example:
///     4XNN - Skips one two byte instruction if the value in VX is not equal to NN
///     40A0 - Skips one two byte instruction if the value in V0 is not equal to 0xA0
fn conditionalSkipNeq(hardware: *core.Hardware, op: *const core.Opcode) void {
    const t: u8 = @as(u8, op.three) << 4;
    const o: u8 = @as(u8, op.four);

    const value: u8 = t | o;

    // Skip the next two byte instruction if the value in VX is not equal to NN
    if (hardware.V[op.two] != value) {
        hardware.PC += 2;
    }
}

/// Skips one two byte instruction if the value in VX is equal to the value in VY.
///
/// Example:
///     5XY0 - Skips one two byte instruction if the value in VX is equal to the value in VY
///     5560 - Skips one two byte instruction if the value in V5 is equal to the value in V6
fn conditionalSkipXYEq(hardware: *core.Hardware, op: *const core.Opcode) void {
    if (hardware.V[op.two] == hardware.V[op.three]) {
        hardware.PC += 2;
    }
}

/// Skips one two byte instruction if the value in VX is not equal to the value in VY.
///
/// Example:
///     9XY0 - Skips one two byte instruction if the value in VX is not equal to the value in VY
///     9A50 - Skips one two byte instruction if the value in VA is not equal to the value in V5
fn conditionalSkipXYNeq(hardware: *core.Hardware, op: *const core.Opcode) void {
    if (hardware.V[op.two] != hardware.V[op.three]) {
        hardware.PC += 2;
    }
}

/// VX is set to the value of VY.
///
/// Example:
///     8XY0 - VX is set to the value of VY
///     8A40 - VA is set to the value of V4
fn larSetVXVY(hardware: *core.Hardware, op: *const core.Opcode) void {
    hardware.V[op.two] = hardware.V[op.three];
}

/// VX is set to the bitwise OR of VX and VY.
///
/// Example:
///     8XY1 - VX is set to the bitwise OR of VX and VY
///     8A41 - VA is set to the bitwise OR of VA and V4
fn larBitwiseOr(hardware: *core.Hardware, op: *const core.Opcode) void {
    hardware.V[op.two] |= hardware.V[op.three];
}

/// VX is set to the bitwise AND of VX and VY.
///
/// Example:
///     8XY2 - VX is set to the bitwise AND of VX and VY
///     8B22 - VB is set to the bitwise AND of VB and V2
fn larBitwiseAnd(hardware: *core.Hardware, op: *const core.Opcode) void {
    hardware.V[op.two] &= hardware.V[op.three];
}

/// VX is set to the bitwise XOR of VX and VY.
///
/// Example:
///     8XY3 - VX is set to the bitwise XOR of VX and VY
///     8013 - V0 is set to the bitwise XOR of V0 and V1
fn larBitwiseXor(hardware: *core.Hardware, op: *const core.Opcode) void {
    hardware.V[op.two] ^= hardware.V[op.three];
}

/// VX is set to the value of VX plus the value of VY. Unlike `addVX`
/// if the value results in an overflow the flag bit is set.
///
/// Example:
///     8XY4 - VX is set to the value of VX plus the value of VY
///     8494 - V4 is set to the value of V4 plus the value of V9
fn larAdd(hardware: *core.Hardware, op: *const core.Opcode) void {
    const ov = @addWithOverflow(hardware.V[op.two], hardware.V[op.three]);

    // Update the flag bit based on whether or not overflow occurred
    hardware.V[0xF] = if (ov[1] != 0) 1 else 0;
    hardware.V[op.two] = ov[0];
}

/// VX is set to the value of VX minus VY. Prior to performing the subtraction
/// the flag bit is set if the minuend (VX) is larger than the subtrahend (VY).
///
/// Example:
///     8XY5 - VX is set to the value of VX minus VY
///     8385 - V3 is set to the value of V3 minus V8
fn larSubtractVXVY(hardware: *core.Hardware, op: *const core.Opcode) void {
    const vx = hardware.V[op.two];
    const vy = hardware.V[op.three];

    hardware.V[0xF] = if (vx > vy) 1 else 0;

    const ov = @subWithOverflow(vx, vy);
    hardware.V[op.two] = ov[0];
}

/// VX is set to the value of VY minus VX. Prior to performing the subtraction
/// the flag bit is set if the minuen (VY) is larger than the subtrahend (VX).
///
/// Example:
///     8XY7 - VX is set to the value of VY minus VX
///     88E7 - V8 is set to the value of VE minus V8
fn larSubtractVYVX(hardware: *core.Hardware, op: *const core.Opcode) void {
    const vx = hardware.V[op.two];
    const vy = hardware.V[op.three];

    hardware.V[0xF] = if (vy > vx) 1 else 0;

    const ov = @subWithOverflow(vy, vx);
    hardware.V[op.two] = ov[0];
}

/// Shifts the value in VX one bit to the right. Sets the flag bit if
/// the bit being shifted out was 1.
///
/// Configurable: Use `set_vx_to_vy_on_shift` in order to set VX as VY for shifts.
///
/// Example:
///     8XY6 - Shifts the value of VX one bit to the right
///     8BC6 - Shifts the value of VB one bit to the right
fn larRightShift(hardware: *core.Hardware, op: *const core.Opcode) void {
    if (set_vx_to_vy_on_shift) {
        hardware.V[op.two] = hardware.V[op.three];
    }

    // Mask the first bit that'll be shifted out by the right shift to determine the flag bit
    hardware.V[0xF] = hardware.V[op.two] & 0b1;
    // Perform the right shift by one bit
    hardware.V[op.two] >>= 1;
}

/// Shifts the value in VX one bit to the left. Sets the flag bit if
/// the bit being shifted out was 1.
///
/// Configurable: Use `set_vx_to_vy_on_shift` in order to set VX as VY for shifts.
///
/// Example:
///     8XYE - Shifts the value of VX one bit to the left
///     8BCE - Shifts the value of VB one bit to the left
fn larLeftShift(hardware: *core.Hardware, op: *const core.Opcode) void {
    if (set_vx_to_vy_on_shift) {
        hardware.V[op.two] = hardware.V[op.three];
    }

    // Shift the most significant bit that'll be shifted out by the left shift to determine the flag bit
    hardware.V[0xF] = hardware.V[op.two] >> 7;
    // Perform the left shift bit
    hardware.V[op.two] <<= 1;
}

/// Generates a random number, binary ANDs it with the value provided in the opcode, and
/// stores the result in VX.
///
/// Example:
///     CXNN - Generates a random u8, performs a binary AND with the value NN, and stores the result in VX
///     CXBB - Generates a random u8, performs a binary AND with the value BB, and stores the result in VX
fn larRandom(hardware: *core.Hardware, op: *const core.Opcode) void {
    const t: u8 = @as(u8, op.three) << 4;
    const o: u8 = @as(u8, op.four);

    const value: u8 = t | o;
    const rand = hardware.randomizer.int(u8);
    const value_and_rand = value & rand;

    hardware.V[op.two] = value_and_rand;
}

/// Skips one instruction if the key corresponding to the value in VX is pressed.
/// The keyboard has 16 keys, so the hex value stored in VX is the key being evaluated.
///
/// Example:
///     EX9E - Skips an instruction if the key corresponding to the value in VX is pressed
///     E29E - Skips an instruction if the key corresponding to the value in V2 is pressed
fn skipIfKeyPressed(hardware: *core.Hardware, op: *const core.Opcode) void {
    const key = hardware.V[op.two];

    // We can use the hex value directly since the keys are stored in the first 16 registers
    if (hardware.memory[key] == 1) {
        // Skip an instruction if the key is pressed
        hardware.PC += 2;
    }
}

/// Skips one instruction is the key corresponding to the value in VX is not pressed.
/// The keyboard has 16 keys, so the hex value stored in VX is the key being evaluated.
///
/// Example:
///     EXA1 - Skips an instruction if the key corresponding to the value in VX is not pressed
///     E2A1 - Skips an instruction if the key corresponding to the value in V2 is not pressed
fn skipIfKeyNotPressed(hardware: *core.Hardware, op: *const core.Opcode) void {
    const key = hardware.V[op.two];

    // We can use the hex value directly since the keys are stored in the first 16 registers
    if (hardware.memory[key] == 0) {
        // Skip an instruction if the key is not pressed
        hardware.PC += 2;
    }
}

/// Sets VX to the current value of the delay timer.
///
/// Example:
///     FX07 - Sets VX to the value of the delay timer
///     FA07 - Sets VA to the value of the delay timer
fn setVXToDelayTimer(hardware: *core.Hardware, op: *const core.Opcode) void {
    hardware.V[op.two] = hardware.delay_timer;
}

/// Sets the delay timer to the current value of VX.
///
/// Example:
///     FX15 - Sets the delay timer to the value of VX
///     FB15 - Sets the delay timer to the value of VB
fn setDelayTimerToVX(hardware: *core.Hardware, op: *const core.Opcode) void {
    hardware.delay_timer = hardware.V[op.two];
}

/// Sets the sound timer to the current value of VX.
///
/// Example:
///     FX18 - Sets the sound timer to the value of VX
///     FC18 - Sets the sound timer to the value of VC
fn setSoundTimerToVX(hardware: *core.Hardware, op: *const core.Opcode) void {
    hardware.sound_timer = hardware.V[op.two];
}

/// The index register gets the value in VX added to it.
///
/// Example:
///     FX1E - Adds the value in VX to the current value in the index register
///     F41E - Adds the value in V4 to the current value in the index register
fn addVXToIndex(hardware: *core.Hardware, op: *const core.Opcode) void {
    const vx = hardware.V[op.two];
    const ov = @addWithOverflow(hardware.I, vx);

    // Update the flag bit based on whether or not overflow occurred
    // Seems to be only required by "Spacefight 2091!", but it doesn't hurt to support it since the Amiga CHIP-8 implementation did
    hardware.V[0xF] = if (ov[1] != 0) 1 else 0;
    hardware.I = ov[0];
}

/// Stops executing instructions and waits for key input, puts the input key in VX.
/// Performs the stop by decrementing the program counter so the last instruction is constantly re-fetched.
///
/// Example:
///     FX0A - Blocks instruction execution until a key is pressed, the hex value for the key is then stored in VX
///     F10A - Blocks instruction execution until a key is pressed, the hex value for the key is then stored in V1
fn getKey(hardware: *core.Hardware) void {
    // Repeat this instruction while a key hasn't been pressed
    if (!hardware.was_key_pressed_this_frame) {
        hardware.PC -= 2;
    }
}

/// The index register is set to the address of the hexadecimal character in VX.
///
/// Example:
///     FX29 - I is set to the address of the hexadecimal character in VX
///     F929 - I is set to the address of the hexadecimal character in V9
fn fontCharacter(hardware: *core.Hardware, op: *const core.Opcode) void {
    // 0x050 is the starting address for the system font and each character has 5 bytes
    const destination_address: u8 = 5 * hardware.V[op.two];
    const ov = @addWithOverflow(core.system_font_starting_address, destination_address);

    if (ov[1] == 0) {
        hardware.I = ov[0];
    } else {
        std.log.err("Overflowed when accessing a font character! Font characters are only accessible in the range of 0x50 - 0xA0.\n\tdestination_address: {x}", .{destination_address});
    }
}

/// Takes the number in VX and splits it into three decimal digits and stores them in the address pointed to in I, I+1, and I+2.
///
/// Example:
///    FX33 - The hex number in VX is split into it's components (only 8-bits, so max 255) and each individual component is stored in I, I+1, and I+2 respectively
///    F233 - The hex number in VX (125) is split into it's components (1, 2, and 5) and each individual component is stored in I (1), I+1 (2), and I+2 (5) respectively
fn binaryCodedDecimalConversion(hardware: *core.Hardware, op: *const core.Opcode) void {
    var vx: u8 = hardware.V[op.two];

    var i: u8 = 0;
    var digits: [3]u8 = .{0} ** 3;
    while (vx > 0) : (i += 1) {
        digits[i] = vx % 10;
        vx /= 10;
    }

    // `digits` will contain each digit in the form [ones, tens, hundreds]
    // According to the CHIP-8 spec, these should be laid out from I [hundreds, tens, ones], which is why we reverse the order
    const I: u16 = hardware.I;
    hardware.memory[I] = digits[2];
    hardware.memory[I + 1] = digits[1];
    hardware.memory[I + 2] = digits[0];
}

/// Stores the values from V0 to VX, starting with the current address in the index register.
///
/// Example:
///    FX55 - Starting at V0 stores addresses in the index register until VX is stored in I+X (e.g., V0 -> I, V1 -> I+1, ..., VX -> I+X)
///    F255 - Starting at V0 stores addresses in the index register until V2 is stored in I+2 (e.g., V0 -> I, V1 -> I+1, V2 -> I+2)
fn storeMemory(hardware: *core.Hardware, op: *const core.Opcode) void {
    const x = op.two;
    const I = hardware.I;

    // Note: We're using the "modern" behaviour here, I will remain the same after values are stored
    for (0..x + 1) |i| {
        const v = hardware.V[i];
        hardware.memory[I + i] = v;
    }
}

/// Loads the values from I, I+1, ..., I+X and loads them into the variable registers, until VX is loaded.
///
/// Example:
///    FX65 - Loads the values from I, I+1, ..., I+X until VX is loaded (e.g, I -> V0, I+1 -> V1, ..., I+X -> VX)
///    F565 - Loads the values from I, I+1, I+2, I+3, I+4, I+5 until V5 is loaded (e.g., I -> V0, I+1 -> V1, I+2 -> V2, I+3 -> V3, I+4 -> V4, I+5 -> V5)
fn loadMemory(hardware: *core.Hardware, op: *const core.Opcode) void {
    const x = op.two;
    const I = hardware.I;

    for (0..x + 1) |i| {
        const ix = hardware.memory[I + i];
        hardware.V[i] = ix;
    }
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
        while (shift_index >= 0 and x_index <= 8) : (x_index += 1) {
            // If drawing reaches the right edge of the screen, go to the next row.
            if ((x + x_index) >= core.display_width_in_pixels) {
                break;
            }

            // If this is logged something is likely _very_ wrong (especially with the check above).
            // Log and display some debugging information as this would've caused a crash anyways
            if ((y + i) >= core.display_height_in_pixels or (x + x_index) >= core.display_width_in_pixels) {
                std.log.err("Screen is drawing out of bounds! Check the decomp below for more info...\n", .{});
                std.log.err("\thardware.display[{d} + {d}][{d} + {d}] => hardware.display[{d}][{d}]\n", .{ y, i, x, x_index, y + i, x + x_index });
                break;
            }

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

fn unimplementedOpDump(op: *const core.Opcode) void {
    std.log.err("Panic! Unimplemented opcode detected! ({X})", .{op.value});
}

fn isDrawOp(op: *const core.Opcode) bool {
    return op.value == 0x00E0 or op.one == 0xD;
}

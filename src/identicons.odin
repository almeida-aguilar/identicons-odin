package identicos

import "core:fmt"
import "core:crypto/sha2"
import "core:strings"
import "core:os"
import "core:flags"
import stbi "vendor:stb/image"

Canvas :: struct {
	width:    uint,
	height:   uint,
	channels: uint,
	pixels:   []u8,
}

canvas_draw_pixel :: proc(canvas: ^Canvas, x: uint, y: uint, color: [3]u8) {
	if x >= canvas.width || y >= canvas.height {
		return
	}
	
	idx := (y * canvas.width + x) * canvas.channels
	canvas.pixels[idx + 0] = color.r
	canvas.pixels[idx + 1] = color.g
	canvas.pixels[idx + 2] = color.b
}

canvas_fill :: proc(canvas: ^Canvas, color: [3]u8) {
	for y: uint = 0; y < canvas.height; y += 1 {
		for x: uint = 0; x < canvas.width; x += 1 {
			canvas_draw_pixel(canvas, x, y, color)
		}
	}

}
canvas_init :: proc(canvas: ^Canvas, width: uint, height: uint, channels: uint, color: [3]u8 = {255, 255, 255}) {
    total_bytes := width * height * channels
    
    canvas.width    = width
    canvas.height   = height
    canvas.channels = channels
    canvas.pixels   = make([]u8, total_bytes)
    
    canvas_fill(canvas, color)
}

canvas_deinit :: proc(canvas: ^Canvas) {
	delete(canvas.pixels)
	canvas.pixels = nil
}

canvas_draw_rectangle :: proc(canvas: ^Canvas, position: [2]uint, size: [2]uint, color: [3]u8) {
	if position.x + size.x > canvas.width || position.y + size.y > canvas.height {
		return
	}
	
	for y: uint = position.y; y < position.y + size.y; y += 1 {
		for x: uint = position.x; x < position.x + size.x; x += 1 {
			canvas_draw_pixel(canvas, x, y, color)
		}
	}
}

hash_string :: proc(input: string) -> [32]u8 {
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, transmute([]byte)input)
	hash: [32]u8
	sha2.final(&ctx, hash[:])
	return hash
}

hash_to_identicon :: proc(hash: [32]u8) -> [5][5]uint {
	grid: [5][5]uint
	
	for i := 0; i < 15; i += 1 {
		row := i / 3
		col := i % 3
		grid[row][col] = uint(hash[i] % 2)
	}
	
	for row := 0; row < 5; row += 1 {
		grid[row][4] = grid[row][0]
		grid[row][3] = grid[row][1]
	}
	
	return grid
}

hash_to_color :: proc(hash: [32]u8) -> [3]u8 {
	return [3]u8{
		hash[15] % 200 + 55,
		hash[16] % 200 + 55,
		hash[17] % 200 + 55,
	}
}

Cli_Args :: struct {
	input:  string `args:"pos=0,required" usage:"Name or text to generate the identicon from"`,
	output: string `usage:"Output filename (e.g. 'my_identicon.jpg')"`,
}

identicon_generate :: proc(input: string, output_filename: string) -> bool {
	WIDTH :: 420
	HEIGHT :: 420
	MARGIN :: 35
	CELL_SIZE :: 70
	
	hash := hash_string(input)
	color := hash_to_color(hash)
	grid := hash_to_identicon(hash)
	
	canvas : Canvas
	canvas_init(&canvas, WIDTH, HEIGHT, 3, {255, 255, 255})
	defer canvas_deinit(&canvas)
	
	for row: uint = 0; row < 5; row += 1 {
		for col: uint = 0; col < 5; col += 1 {
			if grid[row][col] == 1 {
				pos := [2]uint{
					MARGIN + col * CELL_SIZE,
					MARGIN + row * CELL_SIZE,
				}
				size := [2]uint{CELL_SIZE, CELL_SIZE}
				canvas_draw_rectangle(&canvas, pos, size, color)
			}
		}
	}
	
	data_ptr := raw_data(canvas.pixels)
	
	c_filename := strings.clone_to_cstring(output_filename)
	defer delete(c_filename)
	
	success := stbi.write_jpg(c_filename, i32(canvas.width), i32(canvas.height), i32(canvas.channels), data_ptr, 90)
	
	return success != 0
}

print_usage :: proc() {
	fmt.println("identicos - generate an identicon from a piece of text")
	fmt.println()
	fmt.println("Usage:")
	fmt.println("  identicos <input> [-output:<file>]")
	fmt.println()
	fmt.println("Arguments:")
	fmt.println("  input           Text or name to generate the identicon from (required)")
	fmt.println("  -output:<file>  Output filename (e.g. 'my_identicon.jpg')")
	fmt.println()
	fmt.println("Example:")
	fmt.println("  identicos alice -output:alice.jpg")
}

main :: proc() {
	for arg in os.args[1:] {
		if arg == "-help" || arg == "-h" {
			print_usage()
			os.exit(0)
		}
	}

	args: Cli_Args
	if parse_err := flags.parse(&args, os.args[1:]); parse_err != nil {
		print_usage()
		os.exit(1)
	}

	output_filename := args.output
	if output_filename == "" {
		output_filename = fmt.tprintf("%s_identicon.jpg", args.input)
	}

	fmt.printfln("Generating identicon for: %s -> %s", args.input, output_filename)
	if identicon_generate(args.input, output_filename) {
		fmt.println("  Success!")
	} else {
		fmt.eprintln("  Error generating the image.")
		os.exit(1)
	}
}

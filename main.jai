main :: () {
    #if OS == .WINDOWS {
        Windows.SetProcessDPIAware();
        Windows.timeBeginPeriod(1);
    }

    WANTED_MSAA :: 8;

    window = create_window(window_width, window_height, "Image Viewer", wanted_msaa = WANTED_MSAA);
    Simp.prepare_window(window, wanted_msaa = WANTED_MSAA);

    #if OS == .WINDOWS {
        Windows.DragAcceptFiles(window, xx true);
    }

    window_width, window_height = Simp.get_render_dimensions(window);

    Simp.set_render_target(window, .LEFT_HANDED);

    stbi_set_flip_vertically_on_load(1);

    raw_image = stbi_load("image.jpeg", *raw_image_width, *raw_image_height, *raw_image_channels, 0);
    assert(raw_image != null);

    update_image();

    ui_init();

    quit := false;
    while !quit {
        current_time = seconds_since_init();

        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);

            window_width = it.width;
            window_height = it.height;

            update_image();
        }

        for Input.events_this_frame {
            getrect_handle_event(it);

            if it.type == {
                case .QUIT;
                    quit = true;

                case .KEYBOARD;
                    if it.key_pressed && it.key_code == .ESCAPE then quit = true;

                    if it.modifier_flags.ctrl_pressed && it.key_code == #char "O" && it.key_pressed {
                        file, success := platform_open_file();
                        if success then replace_open_image(file);
                    }

                case .DRAG_AND_DROP_FILES;
                    file := it.files[0];
                    replace_open_image(file);
            }
        }

        draw_one_frame();

        reset_temporary_storage();

        sleep_milliseconds(10);
    }

    report_memory_leaks();
}

draw_one_frame :: () {
    Simp.clear_render_target(.094, .094, .094, 1);

    x, y, width, height := get_dimensions(window, true);
    ui_per_frame_update(window, width, height, current_time);

    draw_image();
    draw_rotate_buttons();

    Simp.swap_buffers(window);
}

draw_image :: () {
    Simp.set_shader_for_images(*image);
    Simp.immediate_begin();

    w := cast(float) image.width;
    h := cast(float) image.height;

    offset := Vector2.{
        (window_width - w) / 2,
        (window_height - h) / 2,
    };

    p0 := offset + .{ 0, 0 };
    p1 := offset + .{ 0, h };
    p2 := offset + .{ w, h };
    p3 := offset + .{ w, 0 };

    uv0 := Vector2.{ 0, 1 };
    uv1 := Vector2.{ 0, 0 };
    uv2 := Vector2.{ 1, 0 };
    uv3 := Vector2.{ 1, 1 };

    p_center := offset + Vector2.{ w / 2, h / 2 };

    p0 = rotate_around_center(p0, p_center, image_rotation);
    p1 = rotate_around_center(p1, p_center, image_rotation);
    p2 = rotate_around_center(p2, p_center, image_rotation);
    p3 = rotate_around_center(p3, p_center, image_rotation);

    Simp.immediate_quad(p0, p1, p2, p3, uv0 = uv0, uv1 = uv1, uv2 = uv2, uv3 = uv3);
    Simp.immediate_flush();
}

draw_rotate_buttons :: () {
    BUTTON_WIDTH :: 60.0;
    BUTTON_HEIGHT :: 60.0;

    r := get_rect(window_width - BUTTON_WIDTH, window_height - BUTTON_HEIGHT * 2, BUTTON_WIDTH, BUTTON_HEIGHT * 2);

    r1, r2 := cut_top(r, BUTTON_HEIGHT);

    pressed := button(r1, "Left");
    if pressed then rotate_counter_clockwise();

    pressed = button(r2, "Right");
    if pressed then rotate_clockwise();
}

rotate_counter_clockwise :: () {
    image_rotation += PI / 2;

    if values_are_close(image_rotation, TAU) then image_rotation = 0;

    update_image();
}

rotate_clockwise :: () {
    image_rotation -= PI / 2;

    if values_are_close(image_rotation, -TAU) then image_rotation = 0;

    update_image();
}

update_image :: () {
    modified_image = raw_image;
    modified_image_width = raw_image_width;
    modified_image_height = raw_image_height;

    // rotate();
    resize();
    texture_load_from_raw_memory(*image, modified_image, modified_image_width, modified_image_height, raw_image_channels);
}

resize :: () {
    w := cast(float) modified_image_width;
    h := cast(float) modified_image_height;

    aspect_ratio := w / h;
    target_width := cast(float) window_width;
    target_height := cast(float) window_height;

    if values_are_close(abs(image_rotation), PI / 2) || values_are_close(abs(image_rotation), TAU - PI / 2) {
        target_width = cast(float) window_height;
        target_height = cast(float) window_width;
    }

    if (target_width / target_height) > aspect_ratio {
        target_width = target_height * aspect_ratio;
    } else {
        target_height = target_width / aspect_ratio;
    }

    resized_image := talloc(cast(int) target_width * cast(int) target_height * raw_image_channels);

    result := stbir_resize_uint8(modified_image, modified_image_width, modified_image_height, 0, resized_image, xx target_width, xx target_height, 0, raw_image_channels);
    assert(result != 0);

    modified_image = resized_image;
    modified_image_width = xx target_width;
    modified_image_height = xx target_height;
}

rotate :: () {
    sin_radius := sin(image_rotation);
    cos_radius := cos(image_rotation);

    width := cast(int) (abs(raw_image_width * cos_radius) + abs(raw_image_height * sin_radius));
    height := cast(int) (abs(raw_image_height * cos_radius) + abs(raw_image_width * sin_radius));

    bytes_per_pixel := raw_image_channels;
    rotated_image := cast(*u8) talloc(width * height * bytes_per_pixel);

    for y: 0..height - 1 {
        for x: 0..width - 1 {
            old_x := ((x - width / 2) * cos_radius + (y - height / 2) * sin_radius) + raw_image_width / 2;
            old_y := ((y - height / 2) * cos_radius - (x - width / 2) * sin_radius) + raw_image_height / 2;

            if old_x >= 0 && old_x < cast(float) raw_image_width && old_y >= 0 && old_y < cast(float) raw_image_height {
                x1 := cast(int) floor(old_x);
                y1 := cast(int) floor(old_y);
                x2 := min(x1 + 1, raw_image_width - 1);
                y2 := min(y1 + 1, raw_image_height - 1);

                px := old_x - x1;
                py := old_y - y1;

                for i: 0..bytes_per_pixel - 1 {
                    idx1 := (y1 * raw_image_width + x1) * bytes_per_pixel + i;
                    idx2 := (y1 * raw_image_width + x2) * bytes_per_pixel + i;
                    idx3 := (y2 * raw_image_width + x1) * bytes_per_pixel + i;
                    idx4 := (y2 * raw_image_width + x2) * bytes_per_pixel + i;

                    f1 := (raw_image + idx1).*;
                    f2 := (raw_image + idx2).*;
                    f3 := (raw_image + idx3).*;
                    f4 := (raw_image + idx4).*;

                    val := f1 * (1 - px) * (1 - py) +
                           f2 * px * (1 - py) +
                           f3 * (1 - px) * py +
                           f4 * px * py;

                    (rotated_image + (y * width + x) * bytes_per_pixel + i).* = cast(u8) val;
                }
            }
        }
    }

    modified_image = rotated_image;
    modified_image_width = xx abs(width);
    modified_image_height = xx abs(height);
}

rotate_around_center :: (p: Vector2, center: Vector2, theta: float) -> Vector2 {
    local := p - center;

    ct := cos(theta);
    st := sin(theta);

    rotated := Vector2.{
        local.x * ct - local.y * st,
        local.x * st + local.y * ct,
    };

    return center + rotated;
}

texture_load_from_raw_memory :: (texture: *Simp.Texture, data: *u8, w: s32, h: s32, channels: s32) {
    bitmap: Simp.Bitmap;
    defer Simp.deinit(*bitmap);

    format: Simp.Texture_Format;
    if channels == {
        case 1; format = .R8;
        case 2; format = .RG8;
        case 3; format = .RGB8;
        case 4; format = .RGBA8;
    }

    Simp.bitmap_alloc(*bitmap, w, h, format);

    memcpy(bitmap.data.data, data, bitmap.stride*bitmap.height);

    Simp.texture_load_from_bitmap(texture, *bitmap);
}

replace_open_image :: (file: string) {
    stbi_image_free(raw_image);

    raw_image = stbi_load(temp_c_string(file), *raw_image_width, *raw_image_height, *raw_image_channels, 0);
    assert(raw_image != null);

    image_rotation = 0;
    update_image();
}

current_time: float64;

window: Window_Type;

window_width  := 1280;
window_height := 720;

image: Simp.Texture;
image_rotation: float;

raw_image: *u8;
raw_image_width: s32;
raw_image_height: s32;
raw_image_channels: s32;

modified_image: *u8;
modified_image_width: s32;
modified_image_height: s32;

#import "Basic" () (MEMORY_DEBUGGER = true);
#import "GetRect_LeftHanded";
#import "GL";
#import "Math";
#import "Sloppy_Math";
#import "stb_image";
#import "stb_image_resize";
#import "Window_Creation";

Input :: #import "Input";
Simp  :: #import "Simp";

#if OS == .WINDOWS {
    Utf8    :: #import "Windows_Utf8";

    platform_open_file :: () -> string, success: bool #must {
        wfilter := Utf8.utf8_to_wide("Image\0*.jpeg;*.jpg;*.png",, temp);

        buffer: [512] u16;

        ofn: Windows.OPENFILENAMEW;
        ofn.lStructSize = size_of(Windows.OPENFILENAMEW);
        ofn.lpstrFilter = wfilter;
        ofn.lpstrFile   = buffer.data;
        ofn.nMaxFile    = buffer.count;
        ofn.Flags       = Windows.OFN_NOCHANGEDIR;

        open_success := Windows.GetOpenFileNameW(*ofn);
        if open_success {
            result, success := Utf8.wide_to_utf8(buffer.data,, temp);
            return result, success;
        }

        return "", false;
    }
}
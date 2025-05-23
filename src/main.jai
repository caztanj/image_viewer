main :: () {
    #if OS == .WINDOWS {
        Windows.SetProcessDPIAware();
        Windows.timeBeginPeriod(1);
    }

    file := "";

    args := get_command_line_arguments(,, temp);

    if args.count > 1 {
        file = args[1];
    }

    init_thread_group();

    WANTED_MSAA :: 8;

    window = create_window(window_width, window_height, "Image Viewer", wanted_msaa = WANTED_MSAA);
    Simp.prepare_window(window, wanted_msaa = WANTED_MSAA);

    #if OS == .WINDOWS {
        Windows.DragAcceptFiles(window, xx true);
    }

    window_width, window_height = Simp.get_render_dimensions(window);

    Simp.set_render_target(window, .LEFT_HANDED);

    stbi_set_flip_vertically_on_load(1);

    if file.count > 0 {
        raw_image = stbi_load(temp_c_string(file), *raw_image_width, *raw_image_height, *raw_image_channels, 0);
        assert(raw_image != null);

        update_image();
    }

    ui_init();

    quit := false;
    while !quit {
        current_time = seconds_since_init();

        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);

            window_width = it.width;
            window_height = it.height;

            if raw_image != null {
                update_image_size();
                update_image();
            }
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
                        if success then load_image_from_file(file);
                    }

                case .DRAG_AND_DROP_FILES;
                    file := it.files[0];
                    load_image_from_file(file);
            }
        }

        draw_one_frame();

        results := get_completed_work(*thread_group);

        for results {
            work := cast(*Work) it;

            if #complete work.type == {
                case .Load_Image;
                    replace_open_image(work.load_image);

                case .Resize_Image;
                    texture_load_from_raw_memory(*image, work.resize_image.image, work.resize_image.width, work.resize_image.height, work.resize_image.channels);
            }

            deinit(work);
        }

        reset_temporary_storage();

        sleep_milliseconds(10);
    }

    #if DEBUG_MEMORY {
        report_memory_leaks();
    }
}

draw_one_frame :: () {
    Simp.clear_render_target(.094, .094, .094, 1);

    x, y, width, height := get_dimensions(window, true);
    ui_per_frame_update(window, width, height, current_time);

    r := get_rect(0, 0, xx width, xx height);

    if raw_image != null then draw_image();

    r_buttons := cut_right(r, 120);
    draw_buttons(r_buttons);

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

draw_buttons :: (r: Rect) {
    BUTTON_WIDTH :: 60.0;
    BUTTON_HEIGHT :: 60.0;

    r_rotate, r_open := cut_bottom(r, BUTTON_HEIGHT * 2);
    r_rotate = cut_right(r_rotate, BUTTON_WIDTH);

    r_rotate_left, r_rotate_right := cut_top(r_rotate, BUTTON_HEIGHT);

    if raw_image != null {
        pressed := button(r_rotate_left, "Left");
        if pressed then rotate_counter_clockwise();

        pressed = button(r_rotate_right, "Right");
        if pressed then rotate_clockwise();
    }

    r_open = cut_bottom(r_open, BUTTON_HEIGHT);

    pressed := button(r_open, "Open");
    if pressed {
        file, success := platform_open_file();
        if success then load_image_from_file(file);
    }
}

rotate_counter_clockwise :: () {
    image_rotation += PI / 2;

    if values_are_close(image_rotation, TAU) then image_rotation = 0;

    update_image();
    update_image_size();
}

rotate_clockwise :: () {
    image_rotation -= PI / 2;

    if values_are_close(image_rotation, -TAU) then image_rotation = 0;

    update_image();
    update_image_size();
}

update_image_size :: () {
    w := cast(float) raw_image_width;
    h := cast(float) raw_image_height;

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

    image.width = xx target_width;
    image.height = xx target_height;
}

update_image :: () {
    work := New(Work);
    work.type = .Resize_Image;

    work.resize_image.image    = raw_image;
    work.resize_image.width    = raw_image_width;
    work.resize_image.height   = raw_image_height;
    work.resize_image.channels = raw_image_channels;
    work.resize_image.rotation = image_rotation;

    add_work(*thread_group, work, "Resize_Image");
}

resize :: (image: *u8, width: s32, height: s32, channels: s32, rotation: float) -> image: *u8, width: s32, height: s32 {
    w := cast(float) width;
    h := cast(float) height;

    aspect_ratio := w / h;
    target_width := cast(float) window_width;
    target_height := cast(float) window_height;

    if values_are_close(abs(rotation), PI / 2) || values_are_close(abs(rotation), TAU - PI / 2) {
        target_width = cast(float) window_height;
        target_height = cast(float) window_width;
    }

    if (target_width / target_height) > aspect_ratio {
        target_width = target_height * aspect_ratio;
    } else {
        target_height = target_width / aspect_ratio;
    }

    resized_image := alloc(cast(int) target_width * cast(int) target_height * raw_image_channels);

    result := stbir_resize_uint8(image, width, height, 0, resized_image, xx target_width, xx target_height, 0, raw_image_channels);
    assert(result != 0);

    return resized_image, xx target_width, xx target_height;
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

load_image_from_file :: (file: string) {
    w := New(Work);
    w.type = .Load_Image;
    w.load_image.file = copy_string(file);

    add_work(*thread_group, w, "Load_Image");
}

replace_open_image :: (using work: Work_Load_Image) {
    stbi_image_free(raw_image);

    raw_image = image;
    raw_image_width = width;
    raw_image_height = height;
    raw_image_channels = channels;

    image_rotation = 0;
    update_image();
}

// @Todo: Make sure we don't have multiple Load_Image and/or Resize_Image queued.
Work_Type :: enum {
    Load_Image;
    Resize_Image;
}

Work :: struct {
    type: Work_Type;

    union {
        load_image:   Work_Load_Image;
        resize_image: Work_Resize_Image;
    }
}

Work_Load_Image :: struct {
    file: string;

    image: *u8;

    width:    s32;
    height:   s32;
    channels: s32;
}

Work_Resize_Image :: struct {
    image: *u8;

    width:    s32;
    height:   s32;
    channels: s32;

    rotation: float;
}

deinit :: (work: *Work) {
    if #complete work.type == {
        case .Load_Image;
            free(work.load_image.file);

        case .Resize_Image;
            free(work.resize_image.image);
    }

    free(work);
}

worker :: (group: *Thread_Group, thread: *Thread, work: *void) -> Thread_Continue_Status {
    w := cast(*Work) work;

    if #complete w.type == {
        case .Load_Image;
            using w.load_image;
            image = stbi_load(temp_c_string(file), *width, *height, *channels, 0);
            assert(image != null);

        case .Resize_Image;
            using w.resize_image;
            image, width, height = resize(image, width, height, channels, rotation);
    }

    return .CONTINUE;
}

init_thread_group :: () {
    init(*thread_group, 1, worker);

    thread_group.name = "Worker Thread Group";

    start(*thread_group);
}

thread_group: Thread_Group;

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

DEBUG_MEMORY :: false;

#import "Basic" () (MEMORY_DEBUGGER = DEBUG_MEMORY, TEMP_ALLOCATOR_POISON_FREED_MEMORY = DEBUG_MEMORY);
#import "GetRect_LeftHanded";
#import "GL";
#import "Math";
#import "Sloppy_Math";
#import "stb_image";
#import "stb_image_resize";
#import "Thread";
#import "Window_Creation";

Input :: #import "Input";
Simp  :: #import "Simp";

#if OS == .WINDOWS {
    Utf8              :: #import "Windows_Utf8";
    Windows_Resources :: #import "Windows_Resources";

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

    #run {
        Windows_Resources.disable_runtime_console();
    }
}
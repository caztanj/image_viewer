build :: () {
    set_build_options_dc(.{ do_output = false, });

    args := get_build_options().compile_time_command_line;

    release := array_find(args, "-release");

    w := compiler_create_workspace("Image Viewer");

    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);
    options.output_executable_name = "image_viewer";

    if release {
        options.backend = .LLVM;
        options.output_path = "build_release";
    } else {
        options.backend = .X64;
        options.output_path = "build_debug";
    }

    make_directory_if_it_does_not_exist(options.output_path, recursive = true);

    set_build_options(options, w);

    compiler_begin_intercept(w);
    add_build_file("src/main.jai", w);

    while true {
        message := compiler_wait_for_message();

        if message.kind == {
            case .ERROR;
                exit(1);

            case .COMPLETE;
                break;
        }
    }

    compiler_end_intercept(w);
}

#run build();

#import "Basic";
#import "Compiler";
#import "File";
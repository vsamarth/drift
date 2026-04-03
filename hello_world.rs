use std::thread;
use std::time::Duration;

fn main() {
    let message = "Hello, World!";
    let colors = [
        "\x1b[31m", // Red
        "\x1b[33m", // Yellow
        "\x1b[32m", // Green
        "\x1b[36m", // Cyan
        "\x1b[34m", // Blue
        "\x1b[35m", // Magenta
    ];

    println!("\x1b[2J\x1b[H");
    println!("\x1b[?25l");

    for i in 0..message.len() {
        let color = colors[i % colors.len()];
        print!("{}{}", color, &message[..=i]);
        print!("\x1b[0m");
        print!("\r");
        thread::sleep(Duration::from_millis(150));
    }

    println!();
    println!("\x1b[?25h");
}

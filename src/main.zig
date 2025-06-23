const std = @import("std");
const sorted_list = @import("sorted_list.zig");
const WordNode = struct {
    word: [5]u8,
    pub const Context = struct {
        pub fn lt(a: WordNode, b: WordNode) bool {
            return std.mem.order(u8, &a.word, &b.word) == .lt;
        }
        pub fn eq(a: WordNode, b: WordNode) bool {
            return std.mem.eql(u8, &a.word, &b.word);
        }
    };
};
const LetterPosition = struct {
    letter: u8,
    pos: u8,
};
const Rule = union(enum) {
    exclude: u8,
    include: u8,
    include_wrong_pos: LetterPosition,
    include_right_pos: LetterPosition,
    ///Order by enum tag, then their payloads
    pub const Context = struct {
        pub fn lt(a: Rule, b: Rule) bool {
            const tag_order = std.math.order(@intFromEnum(a), @intFromEnum(b));
            if (tag_order != .eq) return tag_order == .lt;
            switch (a) {
                .exclude => |p| return p < b.exclude,
                .include => |p| return p < b.include,
                .include_wrong_pos => |p| {
                    const letter_order = std.math.order(p.letter, b.include_wrong_pos.letter);
                    if (letter_order != .eq) return letter_order == .lt;
                    return p.pos < b.include_wrong_pos.pos;
                },
                .include_right_pos => |p| {
                    const letter_order = std.math.order(p.letter, b.include_right_pos.letter);
                    if (letter_order != .eq) return letter_order == .lt;
                    return p.pos < b.include_right_pos.pos;
                },
            }
        }
        pub fn eq(a: Rule, b: Rule) bool {
            if (@intFromEnum(a) != @intFromEnum(b)) return false;
            switch (a) {
                .exclude => |p| return p == b.exclude,
                .include => |p| return p == b.include,
                .include_wrong_pos => |p| {
                    if (p.letter != b.include_wrong_pos.letter) return false;
                    return p.pos == b.include_wrong_pos.pos;
                },
                .include_right_pos => |p| {
                    if (p.letter != b.include_right_pos.letter) return false;
                    return p.pos == b.include_right_pos.pos;
                },
            }
        }
    };
    pub fn format(self: Rule, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self) {
            .exclude => |p| try writer.print("e{c}", .{p}),
            .include => |p| try writer.print("i{c}", .{p}),
            .include_wrong_pos => |p| try writer.print("n{c}{}", .{ p.letter, p.pos + 1 }),
            .include_right_pos => |p| try writer.print("p{c}{}", .{ p.letter, p.pos + 1 }),
        }
    }
};
const WordMap = sorted_list.SortedList(WordNode, WordNode.Context);
const RuleList = sorted_list.SortedList(Rule, Rule.Context);
const LetterFrequency = struct {
    frequency: u32 = 0,
    letter: u8 = 0,
    pub fn sort(_: void, lhs: LetterFrequency, rhs: LetterFrequency) bool {
        return lhs.frequency > rhs.frequency; //Sort by highest to lowest frequency.
    }
};
inline fn prompt_str(stdout: anytype) !void {
    try stdout.writeAll(comptime ANSI(">>>  ", .{ 1, 34 }));
}
fn rules_added_print(stdout: anytype, rule_list: RuleList) !void {
    try stdout.writeAll(comptime ANSI("Rules Used: [ ", .{ 1, 34 }));
    for (rule_list.list.items) |r| {
        switch (r) {
            .exclude => try stdout.print(comptime ANSI("'{}' ", .{ 1, 30 }), .{r}),
            .include => try stdout.print(comptime ANSI("'{}' ", .{ 1, 34 }), .{r}),
            .include_wrong_pos => try stdout.print(comptime ANSI("'{}' ", .{ 1, 33 }), .{r}),
            .include_right_pos => try stdout.print(comptime ANSI("'{}' ", .{ 1, 32 }), .{r}),
        }
    }
    try stdout.writeAll(comptime ANSI("]\n", .{ 1, 34 }));
}
///Removes '\r' in Windows only when it's a terminal input newline as '\r\n'
inline fn remove_r(opt: []u8) []const u8 {
    return if (@import("builtin").os.tag == .windows) std.mem.trimRight(u8, opt, "\r") else opt;
}
fn load_words(file_name: []const u8, allocator: std.mem.Allocator, stdout: anytype, word_map: *WordMap) !void {
    const words_file_res = std.fs.cwd().openFile(file_name, .{});
    if (words_file_res) |words_file| {
        defer words_file.close();
        word_map.list.clearRetainingCapacity();
        const words_buf = try words_file.reader().readAllAlloc(allocator, try std.fmt.parseIntSizeSuffix("1GiB", 10));
        defer allocator.free(words_buf);
        var word_it = std.mem.tokenizeAny(u8, words_buf, "\n\r \t,");
        while (word_it.next()) |word| {
            if (word.len == 5) {
                var add_word_to_list: [5]u8 = undefined;
                _ = std.ascii.upperString(&add_word_to_list, word);
                const is_word_unique = try word_map.insert_unique(allocator, .{ .word = add_word_to_list });
                if (is_word_unique) {
                    try stdout.print(ANSI("{s} added to list.\n", .{ 1, 32 }), .{add_word_to_list});
                } else try stdout.print(ANSI("{s} already added.\n", .{ 1, 33 }), .{add_word_to_list});
            } else {
                try stdout.print(ANSI("Unable to add '{s}' to list (Not a 5-letter word).\n", .{ 1, 31 }), .{word});
            }
        }
        try stdout.print(ANSI("Loaded words from file '{s}'\n", .{ 1, 32 }), .{file_name});
    } else |e| {
        try stdout.print(ANSI("Unable to load file '{s}'. Error: {any}\n", .{ 1, 31 }), .{ file_name, e });
    }
}
fn parse_rule_str(rule_str: []const u8, allocator: std.mem.Allocator, stdout: anytype, rule_list: *RuleList) !void {
    var rule_added: bool = false;
    var rule_added_ue: Rule = undefined;
    if (rule_str.len == 1 and rule_str[0] == 'r') {
        rule_list.list.clearRetainingCapacity();
        try stdout.writeAll(comptime ANSI("Removed all rules.\n", .{ 1, 32 }));
        return;
    } else if (rule_str.len == 2) {
        switch (rule_str[0]) {
            'e', 'i' => |r| {
                const letter = std.ascii.toUpper(rule_str[1]);
                if (letter < 'A' or letter > 'Z') {
                    try stdout.writeAll(comptime ANSI("Invalid Rule Format.\n", .{ 1, 33 }));
                    return;
                }
                if (r == 'e') {
                    rule_added_ue = .{ .exclude = letter };
                } else rule_added_ue = .{ .include = letter };
                rule_added = try rule_list.insert_unique(allocator, rule_added_ue);
            },
            else => {
                try stdout.writeAll(comptime ANSI("Invalid Rule Format.\n", .{ 1, 33 }));
                return;
            },
        }
    } else if (rule_str.len == 3) {
        const num_str = rule_str[2];
        if (num_str < '1' or num_str > '5') {
            try stdout.writeAll(comptime ANSI("Invalid Rule Format.\n", .{ 1, 33 }));
            return;
        }
        const letter = std.ascii.toUpper(rule_str[1]);
        if (letter < 'A' or letter > 'Z') {
            try stdout.writeAll(comptime ANSI("Invalid Rule Format.\n", .{ 1, 33 }));
            return;
        }
        if (rule_str[0] == 'n') {
            rule_added_ue = .{ .include_wrong_pos = .{
                .letter = letter,
                .pos = num_str - '1',
            } };
            rule_added = try rule_list.insert_unique(allocator, rule_added_ue);
        } else if (rule_str[0] == 'p') {
            rule_added_ue = .{ .include_right_pos = .{
                .letter = letter,
                .pos = num_str - '1',
            } };
            rule_added = try rule_list.insert_unique(allocator, rule_added_ue);
        } else {
            try stdout.writeAll(comptime ANSI("Invalid Rule Format.\n", .{ 1, 33 }));
            return;
        }
    } else {
        try stdout.writeAll(comptime ANSI("Invalid Rule Format.\n", .{ 1, 33 }));
        return;
    }
    if (rule_added) {
        try stdout.print(ANSI("'{}' rule added\n", .{ 1, 32 }), .{rule_added_ue});
    } else {
        _ = rule_list.remove(rule_added_ue);
        try stdout.print(ANSI("'{}' rule ", .{ 1, 32 }) ++ ANSI("deleted\n", .{ 1, 31 }), .{rule_added_ue});
    }
}
pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const stdout_f = std.io.getStdOut();
    var bufstdout = std.io.bufferedWriter(stdout_f.writer());
    const stdout = bufstdout.writer();
    const stdin = std.io.getStdIn().reader();
    const MenuString =
        \\Wordle List Check - Add words and rules to eliminate word choices for the game Wordle
        \\  e to exit
        \\  a to add words
        \\  b to load a list of words (Removes current words in memory)
        \\  d to delete words
        \\  c to clear all words in list
        \\  r to add rules to filter words
        \\  s to save rules list to a file
        \\  t to load rules list from a file (Removes current rules in memory)
        \\  l to list words
        \\  f to list words filtered by rules
        \\  w to count letter frequencies for each word in the word list (filtered by rules)
        \\
        \\words.txt can be created and used to add 5-letter space delimited words on program startup
        \\
    ;
    var word_map: WordMap = .empty;
    defer word_map.deinit(allocator);
    var rule_list: RuleList = .empty;
    defer rule_list.deinit(allocator);
    try load_words("words.txt", allocator, stdout, &word_map);
    main: while (true) {
        try stdout.print(ANSI(MenuString, .{ 1, 34 }), .{});
        try prompt_str(stdout);
        try bufstdout.flush();
        var buf: [3]u8 = undefined;
        if (stdin.readUntilDelimiterOrEof(&buf, '\n')) |buf_opt| {
            if (buf_opt) |opt| {
                if (opt.len == 0) continue;
                const opt2 = remove_r(opt);
                switch (opt2[0]) {
                    'e' => break :main,
                    'a' => {
                        try stdout.writeAll(comptime ANSI("Add a 5-letter word to the list. Add nothing to return to menu.\n", .{ 1, 34 }));
                        add_loop: while (true) {
                            var word_buf: [7]u8 = undefined;
                            try prompt_str(stdout);
                            try bufstdout.flush();
                            if (stdin.readUntilDelimiterOrEof(&word_buf, '\n')) |word_buf_opt| {
                                if (word_buf_opt) |add_word| {
                                    const add_word2 = remove_r(add_word);
                                    if (add_word2.len == 5) {
                                        var add_word_to_list: [5]u8 = undefined;
                                        _ = std.ascii.upperString(&add_word_to_list, add_word2);
                                        const is_word_unique = try word_map.insert_unique(allocator, .{ .word = add_word_to_list });
                                        if (is_word_unique) {
                                            try stdout.print(ANSI("{s} added to list.\n", .{ 1, 32 }), .{add_word_to_list});
                                        } else try stdout.print(ANSI("{s} already added.\n", .{ 1, 33 }), .{add_word_to_list});
                                        continue;
                                    }
                                    if (add_word2.len == 0) break :add_loop;
                                    try stdout.print(ANSI("Unable to add '{s}' to list (Not a 5-letter word).\n", .{ 1, 31 }), .{add_word2});
                                }
                            } else |_| continue;
                        }
                    },
                    'b' => {
                        try stdout.writeAll(comptime ANSI("Write file name to load words. This will overwrite words in memory. Type nothing to cancel.\n", .{ 1, 34 }));
                        try prompt_str(stdout);
                        try bufstdout.flush();
                        const load_res = stdin.readUntilDelimiterAlloc(allocator, '\n', 1024);
                        if (load_res) |load_str| {
                            defer allocator.free(load_str);
                            const load_str2 = remove_r(load_str);
                            if (load_str2.len != 0)
                                try load_words(load_str2, allocator, stdout, &word_map);
                        } else |e| try stdout.print(ANSI("An error occured: {any}\n", .{ 1, 31 }), .{e});
                    },
                    'd' => {
                        try stdout.writeAll(comptime ANSI("Delete a 5-letter word in the list. Add nothing to return to menu.\n", .{ 1, 34 }));
                        rem_loop: while (true) {
                            var word_buf: [7]u8 = undefined;
                            try prompt_str(stdout);
                            try bufstdout.flush();
                            if (stdin.readUntilDelimiterOrEof(&word_buf, '\n')) |word_buf_opt| {
                                if (word_buf_opt) |rem_word| {
                                    const rem_word2 = remove_r(rem_word);
                                    if (rem_word2.len == 5) {
                                        var rem_word_to_list: [5]u8 = undefined;
                                        _ = std.ascii.upperString(&rem_word_to_list, rem_word2);
                                        const word_removed = word_map.remove(.{ .word = rem_word_to_list });
                                        if (word_removed) {
                                            try stdout.print(ANSI("{s} deleted from list.\n", .{ 1, 32 }), .{rem_word_to_list});
                                        } else try stdout.print(ANSI("{s} not in list.\n", .{ 1, 33 }), .{rem_word_to_list});
                                    }
                                    if (rem_word2.len == 0) break :rem_loop;
                                }
                            } else |_| continue;
                        }
                    },
                    'c' => word_map.list.clearRetainingCapacity(),
                    'r' => {
                        const RulesString =
                            \\e to exclude a letter. Format: 'e(letter)'
                            \\i to exclude a letter. Format: 'i(letter)'
                            \\n to include a letter, but not in this position. Format: 'n(letter)1-5'
                            \\p to include a letter in this exact position. Format: 'p(letter)1-5'
                            \\r to remove all rules. Format: 'r'
                            \\Write the same rule again to remove it.
                            \\Add nothing to return to menu.
                            \\
                        ;
                        rules_loop: while (true) {
                            try rules_added_print(stdout, rule_list);
                            try stdout.writeAll(comptime ANSI(RulesString, .{ 1, 34 }));
                            try prompt_str(stdout);
                            try bufstdout.flush();
                            var rules_buf: [5]u8 = undefined;
                            if (stdin.readUntilDelimiterOrEof(&rules_buf, '\n')) |rules_buf_opt| {
                                if (rules_buf_opt) |rule_str| {
                                    const rule_str2 = remove_r(rule_str);
                                    if (rule_str2.len == 0) break :rules_loop;
                                    try parse_rule_str(rule_str2, allocator, stdout, &rule_list);
                                }
                            } else |_| continue;
                        }
                    },
                    's' => {
                        try stdout.writeAll(comptime ANSI("Write file name to save rules. Type nothing to cancel.\n", .{ 1, 34 }));
                        try prompt_str(stdout);
                        try bufstdout.flush();
                        const save_res = stdin.readUntilDelimiterAlloc(allocator, '\n', 1024);
                        if (save_res) |save_str| {
                            defer allocator.free(save_str);
                            const save_str2 = remove_r(save_str);
                            if (save_str2.len != 0) {
                                const save_file_res = std.fs.cwd().createFile(save_str2, .{});
                                if (save_file_res) |save_file| {
                                    defer save_file.close();
                                    for (rule_list.list.items) |r|
                                        try save_file.writer().print("{}\n", .{r});
                                    try stdout.print(ANSI("Saved rules to '{s}'\n", .{ 1, 32 }), .{save_str2});
                                } else |e| try stdout.print(ANSI("An error occured when saving rules to file '{s}': {any}\n", .{ 1, 31 }), .{ save_str2, e });
                            }
                        } else |e| try stdout.print(ANSI("An error occured: {any}\n", .{ 1, 31 }), .{e});
                    },
                    't' => {
                        try stdout.writeAll(comptime ANSI("Write file name to load rules. This will overwrite rules in memory. Type nothing to cancel.\n", .{ 1, 34 }));
                        try prompt_str(stdout);
                        try bufstdout.flush();
                        const load_res = stdin.readUntilDelimiterAlloc(allocator, '\n', 1024);
                        if (load_res) |load_str| {
                            defer allocator.free(load_str);
                            const load_str2 = remove_r(load_str);
                            if (load_str2.len != 0) {
                                const load_file_res = std.fs.cwd().openFile(load_str2, .{});
                                if (load_file_res) |load_file| {
                                    defer load_file.close();
                                    const rules_buf = try load_file.reader().readAllAlloc(allocator, try std.fmt.parseIntSizeSuffix("1GiB", 10));
                                    defer allocator.free(rules_buf);
                                    rule_list.list.clearRetainingCapacity();
                                    var rule_it = std.mem.tokenizeAny(u8, rules_buf, "\n\r \t,");
                                    while (rule_it.next()) |rule_str|
                                        try parse_rule_str(rule_str, allocator, stdout, &rule_list);
                                } else |e| try stdout.print(ANSI("An error occured when loading rules from file '{s}': {any}\n", .{ 1, 31 }), .{ load_str2, e });
                            }
                        } else |e| try stdout.print(ANSI("An error occured: {any}\n", .{ 1, 31 }), .{e});
                    },
                    'l' => {
                        try stdout.writeAll(comptime ANSI("Words in list: [ ", .{ 1, 34 }));
                        try stdout.writeAll("\x1b[1;32m");
                        for (word_map.list.items) |wn|
                            try stdout.print("{s} ", .{wn.word});
                        try stdout.writeAll("\x1b[0m");
                        try stdout.print(ANSI("]\nTotal words: {}\n", .{ 1, 34 }), .{word_map.list.items.len});
                    },
                    'f' => {
                        try rules_added_print(stdout, rule_list);
                        try stdout.writeAll(comptime ANSI("Words filtered by rules: [ ", .{ 1, 34 }));
                        try stdout.writeAll("\x1b[1;32m");
                        var filtered_total: usize = 0;
                        skip_word: for (word_map.list.items) |wn| {
                            for (rule_list.list.items) |rule| {
                                switch (rule) {
                                    .exclude => |p| for (wn.word) |ch|
                                        if (ch == p) continue :skip_word,
                                    .include => |p| for (wn.word) |ch| {
                                        if (ch == p) break;
                                    } else continue :skip_word,
                                    .include_wrong_pos => |p| {
                                        var contains: bool = false;
                                        for (wn.word, 0..5) |ch, i| {
                                            if (i == p.pos) {
                                                if (ch == p.letter) continue :skip_word;
                                            } else {
                                                if (ch == p.letter) contains = true;
                                            }
                                        }
                                        if (!contains) continue :skip_word; //Skip if letter doesn't exist, or letter is in the wrong position.
                                    },
                                    .include_right_pos => |p| if (wn.word[p.pos] != p.letter) continue :skip_word,
                                }
                            }
                            try stdout.print("{s} ", .{wn.word});
                            filtered_total += 1;
                        }
                        try stdout.writeAll("\x1b[0m");
                        try stdout.print(ANSI("]\nTotal words: {}\n", .{ 1, 34 }), .{filtered_total});
                    },
                    'w' => {
                        var letter_frequency_arr: [26]LetterFrequency = [1]LetterFrequency{.{}} ** 26;
                        var letter_frequency_by_pos: [5][26]LetterFrequency = [1][26]LetterFrequency{[1]LetterFrequency{.{}} ** 26} ** 5;
                        for (0.., 'A'..'Z' + 1) |i, l| {
                            letter_frequency_arr[i].letter = @truncate(l);
                            for (0..5) |j|
                                letter_frequency_by_pos[j][i].letter = @truncate(l);
                        }
                        skip_word: for (word_map.list.items) |wn| {
                            for (rule_list.list.items) |rule| {
                                switch (rule) {
                                    .exclude => |p| for (wn.word) |ch|
                                        if (ch == p) continue :skip_word,
                                    .include => |p| for (wn.word) |ch| {
                                        if (ch == p) break;
                                    } else continue :skip_word,
                                    .include_wrong_pos => |p| {
                                        var contains: bool = false;
                                        for (wn.word, 0..5) |ch, i| {
                                            if (i == p.pos) {
                                                if (ch == p.letter) continue :skip_word;
                                            } else {
                                                if (ch == p.letter) contains = true;
                                            }
                                        }
                                        if (!contains) continue :skip_word; //Skip if letter doesn't exist, or letter is in the wrong position.
                                    },
                                    .include_right_pos => |p| if (wn.word[p.pos] != p.letter) continue :skip_word,
                                }
                            }
                            var lmap: u32 = 0;
                            for (wn.word, 0..) |ch, pos| {
                                const letter_i: u8 = ch - 'A';
                                const adj_ch: u5 = @truncate(letter_i);
                                if (lmap & (@as(u32, 1) << adj_ch) == 0)
                                    letter_frequency_arr[letter_i].frequency += 1; //Count each repeated letter once.
                                lmap |= (@as(u32, 1) << adj_ch);
                                letter_frequency_by_pos[pos][letter_i].frequency += 1;
                            }
                        }
                        try stdout.writeAll(comptime ANSI("Letter frequencies: [ ", .{ 1, 34 }));
                        try stdout.writeAll("\x1b[1;33m");
                        for (letter_frequency_arr) |lf|
                            if (lf.frequency != 0)
                                try stdout.print("[{c} => {}] ", .{ lf.letter, lf.frequency });
                        try stdout.writeAll("\x1b[0m");
                        std.sort.block(LetterFrequency, &letter_frequency_arr, {}, LetterFrequency.sort);
                        try stdout.writeAll(comptime ANSI(" ]\nThe number represents the number of words this letter appears (Repeated letters count once per word).\nTop 5 frequent letters: [ ", .{ 1, 34 }));
                        try stdout.writeAll("\x1b[1;33m");
                        for (0..5) |i| {
                            const lf = &letter_frequency_arr[i];
                            if (lf.frequency != 0)
                                try stdout.print("[{c} => {}] ", .{ lf.letter, lf.frequency });
                        }
                        try stdout.writeAll("\x1b[0m");
                        for (0..5) |pos| {
                            try stdout.print(comptime ANSI(" ]\nTop 5 at position {}: [ ", .{ 1, 34 }), .{pos});
                            std.sort.block(LetterFrequency, &letter_frequency_by_pos[pos], {}, LetterFrequency.sort);
                            try stdout.writeAll("\x1b[1;33m");
                            for (0..5) |i| {
                                const lf = &letter_frequency_by_pos[pos][i];
                                if (lf.frequency != 0)
                                    try stdout.print("[{c} => {}] ", .{ lf.letter, lf.frequency });
                            }
                            try stdout.writeAll("\x1b[0m");
                        }
                        try stdout.writeAll(comptime ANSI(" ]\n", .{ 1, 34 }));
                    },
                    else => {},
                }
            } else continue;
        } else |_| continue;
    }
}
/// Comptime ANSI escape codes wrapping a string. Escape codes are tuples of u8.
pub fn ANSI(comptime str: []const u8, comptime esc_codes: anytype) []const u8 {
    var return_str: []const u8 = "\x1b[";
    for (0..esc_codes.len) |i| {
        const u8_str = std.fmt.comptimePrint("{}", .{esc_codes[i]});
        return_str = return_str ++ u8_str ++ if (i != esc_codes.len - 1) ";" else "m";
    }
    return_str = return_str ++ str ++ "\x1b[0m";
    return return_str;
}
test {
    _ = @import("sorted_list.zig");
}

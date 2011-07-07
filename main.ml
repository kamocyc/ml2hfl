
open Util

exception TimeOut
exception LongInput
exception NoProgress
exception CannotDiscoverPredicate

let log_filename = ref ""
let log_cout = ref stdout
let log_fm = ref Format.std_formatter

let open_log () =
  log_filename := Filename.basename (Filename.temp_file "log" ".ml");
  log_cout := open_out (Flag.log_dir ^ !log_filename);
  log_fm := Format.formatter_of_out_channel !log_cout
let close_log () =
  close_out !log_cout

let write_log_string s =
  Format.fprintf !log_fm "%s\n@." s
let write_log_term t =
  Syntax.print_term_fm_break Syntax.ML false !log_fm t;
  flush !log_cout


let print_info () =
  Format.printf "cycle: %d\n" !Flag.cegar_loop;
  Format.printf "abst: %fsec\n" !Flag.time_abstraction;
  Format.printf "mc: %fsec\n" !Flag.time_mc;
  Format.printf "cegar: %fsec\n" !Flag.time_cegar;
  if Flag.debug then Format.printf "IP: %fsec\n" !Flag.time_interpolant;
  Format.printf "total: %fsec\n" (get_time());
  Format.pp_print_flush Format.std_formatter ()





let main filename in_channel =
  let input_string =
    let s = String.create Flag.max_input_size in
    let n = my_input in_channel s 0 Flag.max_input_size in
      if n = Flag.max_input_size then raise LongInput;
      String.sub s 0 n
  in

  let () = if !Flag.web then write_log_string input_string in
  let tdefs, parsed =
    let lb = Lexing.from_string input_string in
    let _ = lb.Lexing.lex_curr_p <-
      {Lexing.pos_fname = Filename.basename filename;
       Lexing.pos_lnum = 1;
       Lexing.pos_cnum = 0;
       Lexing.pos_bol = 0}
    in
      [], Parser_wrapper.from_use_file (Parser.use_file Lexer.token lb)
  in
  let () = if true then Format.printf "parsed:@.%a\n@." (Syntax.print_term_fm_break Syntax.ML true) parsed in
  let () = Type_check.check parsed in
(*
  let parsed = Syntax.set_target parsed in
  let () = Type_check.check parsed in
  let target = Syntax.copy_poly_funs parsed in
  let () = if !Flag.web then write_log_term target in
  let () = Type_check.check target in
  let () = if Flag.print_source then Format.printf "Source Program:@.%a\n@." Syntax.pp_print_term target in
  let t_ext = Abstract.abst_ext_funs target in
  let () = Type_check.check t_ext in
  let () = if true then Format.printf "AAA@." in
  let abst = Abstract.abstract_mutable t_ext in
  let () = Type_check.check abst in
  let () = if true then Format.printf "AAA@." in
  let cps = CPS.trans abst in
  let () = if Flag.print_cps then Format.printf "CPS-converted Program:@.%a\n@." Syntax.pp_print_term cps in
  let () = if true then Format.printf "parsed:@.%a\n@." (Syntax.print_term_fm_break Syntax.ML true) cps in
  let () = Type_check.check cps in
  let cps =
    let defs, t = Syntax.lift cps in
      List.fold_right
        (fun (f, (xs, t')) t ->
           let flag =
             if List.exists (fun id -> List.mem_assoc id defs) (Syntax.get_fv t')
             then Flag.Recursive
             else Flag.Nonrecursive
           in
             {Syntax.desc=Syntax.Let(flag, f,xs,t', t); Syntax.typ=t.Syntax.typ})
        defs t
  in

  let () = if true then Format.printf "LIFTED:@.%a\n@." Syntax.pp_print_term cps in
  let tdefs = List.map (fun (x, t) -> x, Syntax.fff t) tdefs in
  let cps = Refine.add_preds_ tdefs cps in
  let () = if true then Format.printf "LIFTED:@.%a\n@." Syntax.pp_print_term cps in
  let () = Wrapper.set_datatype_cvc3 cps in
  let t_result, result = CEGAR.cegar tdefs cps [] in
*)
  let target = parsed in
  let t_result, result = CEGAR.cegar [] parsed [] in
    match result with
        None -> print_msg "\nSafe!\n\n"
      | Some (ce,p) ->
          let sol = Wrapper.get_solution p t_result in
            print_msg "Unsafe!\n";
            print_msg "Error trace:";
            List.iter (fun t -> Format.printf "%s; " t) sol;
            if List.length sol <> 0 then Format.printf "@.";
            Syntax.print_ce ce target


let usage =  "Usage: " ^ Sys.executable_name ^ " [options] file\noptions are:"
let spec =
  ["-web", Arg.Set Flag.web, " Web mode";
   "-I", Arg.String (fun dir -> Config.load_path := dir::!Config.load_path),
   "<dir>  Add <dir> to the list of include directories";
  ]


let () =
  if !Sys.interactive
  then ()
  else
    try
      let filename = ref "" in
      let set_file name =
        if !filename <> "" then (Arg.usage spec usage; exit 1);
        filename := name
      in
      let () = Arg.parse spec set_file usage in
      let cin = match !filename with ""|"-" -> stdin | _ -> open_in !filename in
        if !Flag.web then open_log ();
        Wrapper.open_cvc3 ();
        Sys.set_signal Sys.sigalrm (Sys.Signal_handle (fun _ -> raise TimeOut));
        ignore (Unix.alarm Flag.time_limit);
        main Sys.argv.(1) cin;
        print_info ();
        Wrapper.close_cvc3 ();
        if !Flag.web then close_log ()
    with
        Parsing.Parse_error _ -> Format.printf "Parse error.@."; exit 1
      | LongInput -> Format.printf "Input is too long.@."; exit 1
      | TimeOut -> Format.printf "Verification failed (time out).@."; exit 1
      | CEGAR.NoProgress -> Format.printf "Verification failed (new error path not found).@."; exit 1
      | CEGAR.CannotDiscoverPredicate -> Format.printf "Verification failed (new predicate not found).@."; exit 1
      | Typecore.Error (_,e) -> Format.printf "%a@." Typecore.report_error e; exit 1
      | Typemod.Error(_,e) -> Format.printf "%a@." Typemod.report_error e; exit 1
      | Env.Error e -> Format.printf "%a@." Env.report_error e; exit 1
      | Typetexp.Error(_,e) -> Format.printf "%a@." Typetexp.report_error e; exit 1

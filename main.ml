
open Utilities

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
  Syntax.print_term false !log_fm t;
  flush !log_cout


let print_info () =
  Format.printf "cycle: %d\n" !Flag.cegar_loop;
  Format.printf "abst: %fsec\n" !Flag.time_abstraction;
  Format.printf "mc: %fsec\n" !Flag.time_mc;
  Format.printf "cegar: %fsec\n" !Flag.time_cegar;
  if false && Flag.debug then Format.printf "IP: %fsec\n" !Flag.time_interpolant;
  Format.printf "total: %fsec\n" (get_time());
  Format.pp_print_flush Format.std_formatter ()



let spec_file = ref ""

let print_spec spec =
  if spec <> []
  then
    begin
      Format.printf "spec::@. @[";
      List.iter (fun (x,typ) -> Format.printf "@[%a: %a@]@\n" Syntax.print_id x Syntax.print_typ typ) spec;
      Format.printf "@."
    end

let main filename in_channel =
  let input_string =
    let s = String.create Flag.max_input_size in
    let n = my_input in_channel s 0 Flag.max_input_size in
      if n = Flag.max_input_size then raise LongInput;
      String.sub s 0 n
  in

  let () = if !Flag.web then write_log_string input_string in
  let t =
    let lb = Lexing.from_string input_string in
    let () = lb.Lexing.lex_curr_p <-
      {Lexing.pos_fname = Filename.basename filename;
       Lexing.pos_lnum = 1;
       Lexing.pos_cnum = 0;
       Lexing.pos_bol = 0};
    in
    let parsed = Parse.use_file lb in
      Parser_wrapper.from_use_file parsed
  in
  let () = if true then Format.printf "parsed::@. @[%a@.@." Syntax.pp_print_term t in

  let spec =
    if !spec_file = ""
    then []
    else
      let lb = Lexing.from_channel (open_in !spec_file) in
        lb.Lexing.lex_curr_p <-
          {Lexing.pos_fname = Filename.basename !spec_file;
           Lexing.pos_lnum = 1;
           Lexing.pos_cnum = 0;
           Lexing.pos_bol = 0};
        Spec_parser.typedefs Spec_lexer.token lb
  in
  let () = print_spec spec in

  let t = if !Flag.cegar = Flag.CEGAR_DependentType then Trans.set_target t else t in
  let () = if true then Format.printf "set_target::@. @[%a@.@." Syntax.pp_print_term t in
  let top_fun_list,t =
    if !Flag.init_trans
    then
      let t' = Trans.copy_poly_funs t in
      let top_fun_list = Syntax.get_top_funs t' in
      let () = if true && t <> t' then Format.printf "copy_poly::@. @[%a@.@." Syntax.pp_print_term_typ t' in
      let t = t' in
      let spec' = Trans.rename_spec spec t in
      let () = print_spec spec' in
      let t' = Trans.replace_typ spec' t in
      let () = if true && t <> t' then Format.printf "add_preds::@. @[%a@.@." Syntax.pp_print_term' t' in
      let t = t' in
      let t' = Abstract.abstract_recdata t in
      let () = if true && t <> t' then Format.printf "abst_recdata::@. @[%a@.@." Syntax.pp_print_term_typ t' in
      let t = t' in
      let t' = Abstract.abstract_list t in
      let () = if true && t <> t' then Format.printf "abst_list::@. @[%a@.@." Syntax.pp_print_term' t' in
      let t = t' in
(*
      let t' = Abstract.abst_ext_funs t in
      let () = if true && t <> t' then Format.printf "abst_ext_fun::@. @[%a@.@." Syntax.pp_print_term t' in
      let t = t' in
*)
      let t =
        if (match !Flag.refine with Flag.RefineRefType(_) -> true | _ -> false) && !Flag.relative_complete then
          let t = LazyInterface.insert_extra_param t in
          let () = if true then Format.printf "insert_extra_param (%d added)::@. @[%a@.@.%a@.@."
            (List.length !LazyInterface.params) Syntax.pp_print_term t Syntax.pp_print_term' t in
          t
        else
          t
      in
      let t' = CPS.trans t in
      let () = if true && t <> t' then Format.printf "CPS::@. @[%a@.@." Syntax.pp_print_term_typ t' in
      let t = t' in
      let t' = CPS.remove_pair t in
      let () = if true && t <> t' then Format.printf "remove_pair::@. @[%a@.@." Syntax.pp_print_term_typ t' in
        top_fun_list, t'
    else Syntax.get_top_funs t, t
  in

  let () = Type_check.check t Type.TUnit in
  let prog,map = CEGAR_util.trans_prog t in

  let aux x = try [List.assoc (CEGAR_util.trans_var x) map] with Not_found -> [] in
  let top_fun_list = rev_flatten_map aux top_fun_list in

    match !Flag.cegar with
        Flag.CEGAR_SizedType -> LazyInterface.verify [] prog
      | Flag.CEGAR_DependentType ->
	  match CEGAR.cegar prog top_fun_list with
	      prog', None -> Format.printf "Safe!@.@."
	    | _, Some print ->
                Format.printf "Unsafe!@.@.";
                print ()


let usage =  "Usage: " ^ Sys.executable_name ^ " [options] file\noptions are:"
let arg_spec =
  ["-web", Arg.Set Flag.web, " Web mode";
   "-I", Arg.String (fun dir -> Config.load_path := dir::!Config.load_path),
         "<dir>  Add <dir> to the list of include directories";
   "-st", Arg.Unit (fun _ -> Flag.cegar := Flag.CEGAR_SizedType), " Use sized type system for CEGAR";
   "-c", Arg.Unit (fun _ -> Flag.cegar := Flag.CEGAR_SizedType), " Same as -st";
   "-na", Arg.Clear Flag.init_trans, " Do not abstract data";
   "-rs", Arg.Unit (fun _ -> Flag.refine := Flag.RefineRefType(0)),
          " Use refinement type based predicate discovery";
   "-rsn", Arg.Int (fun n -> Flag.refine := Flag.RefineRefType(n)),
          " Use refinement type based predicate discovery";
   "-rd", Arg.Unit (fun _ -> Flag.refine := Flag.RefineRefTypeOld),
          " Use refinement type based predicate discovery (obsolete)";
   "-spec", Arg.String (fun file -> spec_file := file), "<filename>  use <filename> as a specification";
   "-ea", Arg.Unit (fun _ -> Flag.print_eval_abst := true), " Print evaluation of abstacted program";
   "-lift-fv", Arg.Unit (fun _ -> Flag.lift_fv_only := true), " Lift variables which occur in a body";
   "-nc", Arg.Set Flag.new_cegar, " Use new CEGAR method (temporary option)";
   "-trecs", Arg.String Flag.(fun cmd -> trecs := cmd),
             Format.sprintf "<cmd>  Change trecs command yr <cmd> (default: \"%s\")" !Flag.trecs;
   "-old-trecs", Arg.Clear Flag.use_new_trecs, " Use old trecs (temporary option)";
   "-neg-pred", Arg.Set Flag.use_neg_pred, " Use negative predicates";
   "-nap", Arg.Clear Flag.accumulate_predicats, " Turn off predicates accumulation";
   "-rc", Arg.Set Flag.relative_complete, " To be relative complete";
   "-gp", Arg.Set Global.generalize_predicates, " Generalize predicates";
   "-eap", Arg.Set Global.extract_atomic_predicates, " Extract atomic predicates";
   "-enr", Arg.Set Flag.expand_nonrec, " Expand non-recursive functions";
   "-enr2", Arg.Unit (fun _ -> Flag.expand_nonrec := true; Flag.expand_nonrec_init := false),
            " Expand non-recursive functions except functions";
   "-abs-filter", Arg.Set Flag.use_filter, " Turn on the abstraction-filter option";
   "-cps-naive", Arg.Set Flag.cps_simpl, " Use naive CPS transformation";
  ]


let () =
  if !Sys.interactive
  then ()
  else
    try
      let filename = ref "" in
      let set_file name =
        if !filename <> "" then (Arg.usage arg_spec usage; exit 1);
        filename := name
      in
      let () = Arg.parse arg_spec set_file usage in
      let cin = match !filename with ""|"-" -> stdin | _ -> open_in !filename in
        if !Flag.web then open_log ();
        Wrapper.open_cvc3 ();
        Wrapper2.open_cvc3 ();
        Cvc3Interface.open_cvc3 ();
        Sys.set_signal Sys.sigalrm (Sys.Signal_handle (fun _ -> raise TimeOut));
        ignore (Unix.alarm Flag.time_limit);
        main !filename cin;
        print_info ();
        Cvc3Interface.close_cvc3 ();
        Wrapper2.close_cvc3 ();
        Wrapper.close_cvc3 ();
        if !Flag.web then close_log ()
    with
        Syntaxerr.Error err -> Format.printf "%a@." Syntaxerr.report_error err; exit 1
      | LongInput -> Format.printf "Input is too long.@."; exit 1
      | TimeOut -> Format.printf "@.Verification failed (time out).@."; exit 1
      | CEGAR.NoProgress -> Format.printf "Verification failed (new error path not found).@."; exit 1
      | Refine.CannotRefute -> Format.printf "Verification failed (cannot refute an error path).@."; exit 1
      | Typecore.Error (_,e) -> Format.printf "%a@." Typecore.report_error e; exit 1
      | Typemod.Error(_,e) -> Format.printf "%a@." Typemod.report_error e; exit 1
      | Env.Error e -> Format.printf "%a@." Env.report_error e; exit 1
      | Typetexp.Error(_,e) -> Format.printf "%a@." Typetexp.report_error e; exit 1

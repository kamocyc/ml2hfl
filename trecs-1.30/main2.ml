open Utilities;;
open Grammar;;
open Automaton;;
open Typing;;
open Reduce;;

let parseFile filename =
  let in_strm = 
    try
      open_in filename 
    with
	Sys_error _ -> (print_string ("Cannot open file: "^filename^"\n");exit(-1)) in
  let _ = print_string ("analyzing "^filename^"...\n") in
  let lexbuf = Lexing.from_channel in_strm in
  let result =
    try
      Parser.main Lexer.token lexbuf
    with 
	Failure _ -> exit(-1) (*** exception raised by the lexical analyer ***)
      | Parsing.Parse_error -> (print_string "Parse error\n";exit(-1)) in
  let _ = 
    try
      close_in in_strm
    with
	Sys_error _ -> (print_string ("Cannot close file: "^filename^"\n");exit(-1)) 
  in
    result

let parseStdIn() =
  let _ = print_string ("reading standard input ...\n") in
  let in_strm = stdin in
  let lexbuf = Lexing.from_channel in_strm in
  let result =
    try
      Parser.main Lexer.token lexbuf
    with 
	Failure _ -> exit(-1) (*** exception raised by the lexical analyer ***)
      | Parsing.Parse_error -> (print_string "Parse error\n";exit(-1)) 
  in
    result

let factor = ref 1
let te_updated = ref false

exception LimitReached of Typing.te

let rec verify_aux g m steps trials redexes1 freezed dmap cte nte counter =
  if trials =0 then
     raise (LimitReached (hash2list nte))
  else 
     let _ = show_time() in
     let _ = debug "reduce\n" in
     let _ = if !te_updated then (Reduce.red_init(); te_updated := false)
             else () in
     let (redexes1',freezed) = Reduce.red_nsteps steps redexes1 freezed g m nte cte in
     let _ = show_time() in
     let _ = debug "computing type candidates\n" in
    (*** probably we can reset tinfomap for each iteration,
     *** and just add the new type bindings to te.
     *** If te is not updated, we can continue reductions.
     ***)
     let _ = Reduce.set_flag_queue true redexes1' in
     let _ = Reduce.set_flag_freezed true freezed in
     let h = table_create (8*steps) in
     let telist = tinfomap2telist !tinfomap h in
     let telist' = Typing.filter_valid_types telist nte in 
     let _ = if !debugging then 
                (print_string "Candidates:\n";
                 print_te telist')
             else () in
     let te = list2hash telist' in
     (*** for debugging 
     let _ = debug "***********\n" in
     let _ = Typing.print_te (hash2list te) in
     let _ = debug "***********\n" in
     let _ = flush(stdout) in
     ***)
     let _ = show_time() in
     let _ = debug "type checking\n" in
     let te' = compute_te te cte nte dmap g in
     let new_telist = hash2list te' in
     let _ = (te_updated:= not(new_telist=[])) in
     let nte' = add_te nte new_telist in
     let _ = show_time() in
     let _ = debug "type check ended\n" in
     let _ = debug "Inferred type\n" in
     let _ = if !debugging then print_te new_telist else () in 
     let ty = lookup_te g.s nte' in
       if List.mem (ITbase(m.init)) ty
       then hash2list nte'
       else
(**     let te0 = init_te g.nt in
        let _ = check_eterms_in_freezed freezed te0 nte' cte in 
 **)
        (*** Reset the flags of tinfo ***)
        let _ = Reduce.set_flag_queue false redexes1' in
        let _ = Reduce.set_flag_freezed false freezed in
         verify_aux g m (min (!factor*steps) 10000) (trials-1) redexes1' freezed dmap cte nte' (counter+steps)


let verify g m =
  let steps = !Reduce.loop_count in
  let trials = !Reduce.trials_limit in
  let dmap = Grammar.mk_depend g in
  let cte = automaton2cte m in
  let t = initial_redex g m.init in
  let visited = [] in
  let init_queue = Reduce.enqueue_redex (t,visited) empty_queue in
  let nte = init_te g.nt in
  let te = verify_aux g m steps trials init_queue [] dmap cte nte steps in
    (te, cte, dmap)

let verify_debug p = 
  let (g,m) = Conversion.convert p in
  let steps = !Reduce.loop_count in
  let trials = !Reduce.trials_limit in
  let dmap = mk_depend g in
  let cte = automaton2cte m in
  let t = initial_redex g m.init in
  let visited = [] in
  let init_queue = Reduce.enqueue_redex (t,visited) empty_queue in
  let nte = init_te g.nt in
    Reduce.red_nsteps steps init_queue [] g m nte cte

let gen = ref 0

let verifyParseResult (prerules,tr) = 
  let (g, m) = Conversion.convert (prerules,tr) in
  let _ = if !debugging  then print_rules g.r else () in
  try
    let (te,cte,dmap) = verify g m in
    let _ =  (print_te te;
       print_string ("The number of expansions: "^(string_of_int !Reduce.redcount)^"\n"))
    in
      if !gen>0 then
        (print_string ("Generalizing ...\n");
         flush stdout;
 (**       Generalize.generalize te cte dmap g !gen [] **)
         )
      else
        ()
  with
    (Reduce.Error tr) -> 
         (print_string "The property is not satisfied.\nThe error trace is:\n  ";
          Reduce.print_trace tr;
          print_string ("The number of expansions: "^(string_of_int !Reduce.redcount)^"\n"))
  | Reduce.GiveUp -> (print_string "Verification failed (too many candidate types; try the non-sharing mode (-ns)).\n")
  | LimitReached te -> 
     (if !debugging then
        (print_string "Inferred types so far:\n";
         print_te te)
      else ();
      print_string "Verification failed (time out).\n")
  | Grammar.UndefinedNonterminal f -> (print_string ("Undefined non-terminal: "^f^"\n"))
  | Reduce.TArityMismatch (a) ->
       print_string ("Arity mismatch on a terminal symbol: "^a^"\n")
  | Reduce.ArityMismatch (f, farg,arg) ->
       print_string ("Arity mismatch: the arity of function "^f^
                     " is "^(string_of_int(farg))^
                 " but the number of the actual arguments is "^(string_of_int(arg))^"\n")

let string_of_parseresult (prerules, tr) =
  (Syntax.string_of_prerules prerules)^"\n"^(Syntax.string_of_transitions tr)


exception LogFile

let web = ref false 

let rec create_file n =
  if n=0 then
     (print_string "Cannot open a log file\n"; raise LogFile)
  else
     try
      let n = Random.int(15) in
      let prefix = if !web then "/home/koba/horsmc/log/log" else "log" in
      let filename = prefix^(string_of_int n)^".hrs" in
      let fp = open_out_gen [Open_wronly;Open_creat;Open_excl;Open_trunc] 0o666 filename in
         (filename, fp)
     with
       _ -> create_file (n-1)
        

let rec loop() = loop()

let main () =
  let _ = print_string "TRecS 1.17: Type-based model checker for higher-order recursion schemes\n" in
  let start_t = Sys.time() in
  let parseresult =
    try
      let index7 = 1 in
      let index6 =
        if Sys.argv.(index7) = "-nr" then
          (Reduce.recmode := false;
           index7+1)
        else index7 in
      let index5 =
        if Sys.argv.(index6) = "-ns" then
          (Reduce.sharing := false;
           index6+1)
        else index6 in
      let index4 =
        if Sys.argv.(index5) = "-g" then
          (gen := int_of_string(Sys.argv.(index5+1));
           loop_count := 1000;
           index5+2)
        else index5 in
      let index3 = 
        if Sys.argv.(index4) = "-w" then
          (web := true; index4+1)
        else index4 in
      let index2 = 
        if Sys.argv.(index3) = "-d" then
          (Utilities.debugging := true; index3+1)
        else index3 in
      let index1 = 
        if Sys.argv.(index2) = "-b" then
          (Reduce.depthfirst := false; factor := 2; index2+1)
        else if Sys.argv.(index2) = "-bnp" then
          (Reduce.depthfirst := false; factor := 2; Reduce.pruning := false; index2+1)
        else if Sys.argv.(index2) = "-m" then
          (Reduce.mixed := true; index2+1)
        else if Sys.argv.(index2) = "-d2" then
          (Reduce.depth2 := true; index2+1)
        else if Sys.argv.(index2) = "-b2" then
          (Reduce.breadth2 := true; index2+1)
        else index2 in
      let index =
        if Sys.argv.(index1) = "-p" then 
          (Reduce.loop_count := int_of_string(Sys.argv.(index1+1));
           Reduce.trials_limit := int_of_string(Sys.argv.(index1+2));
           index1+3)
        else index1
      in
        parseFile(Sys.argv.(index))
    with
	Invalid_argument _ -> parseStdIn() 
  in
    (verifyParseResult parseresult;
     let end_t = Sys.time() in
     (print_string ("Elapsed Time: "^(string_of_float (end_t -. start_t))^"sec\n");
     ));;

if !Sys.interactive then
  ()
else
  main();;





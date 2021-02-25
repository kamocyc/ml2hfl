open Util
open Mochi_util

let make_temp_file () =
  let dir = "/tmp/mochi" in
  let template = Format.asprintf "%s/%a_XXXXXXXX.ml" dir Time.print_simple !!Unix.time in
  (try Unix.mkdir dir 0o755 with Unix.Unix_error(Unix.EEXIST, _, _) -> ());
  Unix.CPS.open_process_in ("mktemp " ^ template) input_line
  |@> Verbose.printf "Temporary file \"%s\" is created@.@."

let copy_input_file file =
  let temp_file = !!make_temp_file in
  IO.copy_file ~src:file ~dest:temp_file;
  temp_file

let save_input_to_file filenames =
  match filenames with
  | []
  | ["-"] ->
      let filename = if !Flag.use_temp then !!make_temp_file else "stdin.ml" in
      Flag.Input.filenames := [filename];
      IO.output_file filename (IO.input_all stdin)
  | _ ->
      if !Flag.use_temp then
        filenames
        |> List.map copy_input_file
        |> Ref.set Flag.Input.filenames

let trans1 (prog : Syntax.term) =
  print_endline "trans1 (before)";
  print_endline @@ Syntax.show_term prog;
  let tr = Syntax.make_trans () in
  tr.tr_desc <- (fun desc ->
    (* Format.printf "tt=%a\n" Print.desc desc; *)
    match desc with
    | Const Unit -> Const (Int 0)
    | End_of_definitions -> assert false
    | App ({ desc = Const (Rand (ty2, false)) }, _) -> desc
    | _ -> tr.tr_desc_rec desc
  );
  tr.tr_const <- (fun const ->
    match const with
    | Unit -> Int 0
    | _ -> tr.tr_const_rec const);
  tr.tr_typ <- (fun typ ->
    match typ with
    | TBase TUnit -> TBase TInt
    | _ -> tr.tr_typ_rec typ
  );
  tr.tr_decl <- (fun decl ->
    match decl with
    | Decl_let [(
      { name = "main"; typ = (TFun (tyarg, (TBase TUnit))); attr; id},
      { Syntax.desc = desc1;
        typ = (TFun (tyarg2, TBase TUnit)); attr = attr2}
    )] -> begin
      Decl_let [( { Id.name = "main";
        typ = (TFun ({ tyarg with typ = TBase TInt}, (TBase TUnit)));
        id;
        attr
      },
      { Syntax.desc = tr.tr_desc desc1; typ = TFun ({ tyarg2 with typ = TBase TInt}, TBase TUnit); attr = attr2}
      )]
    end
    | _ -> tr.tr_decl_rec decl
  );
  tr.tr_term <- (fun term ->
    match term with
    | { Syntax.desc =
        (Syntax.If (t,
          ({ Syntax.desc = (Syntax.Const Syntax.Unit);
            typ = (Type.TBase Type.TUnit)} as th),
          ({ Syntax.desc =
            (Syntax.App (
              { Syntax.desc =
                (Syntax.Event ("fail", false))},
              [{ Syntax.desc =
                  (Syntax.Const Syntax.Unit);
                  typ = (Type.TBase Type.TUnit)}
                ]
              ));
            typ = (Type.TBase Type.TUnit)} as el)
          ));
        typ = (Type.TBase Type.TUnit); } -> begin
      { term with desc = Syntax.If (tr.tr_term_rec t, th, el) }
    end
    | _ -> tr.tr_term_rec term
  );
  let prog =
    match prog with
    | { desc = Local (decl, descs)} -> begin
      let decl = tr.tr_decl decl in
      let rec go descs =
        match descs with
        | { Syntax.desc = Local (decl, descs) } -> { descs with desc = Local (tr.tr_decl decl, go descs) }
        | { Syntax.desc = End_of_definitions } -> descs
        | _ -> failwith "b"
      in
      { descs with Syntax.desc = Local (decl, go descs) }
    end
    | _ -> failwith "a"
  in
  print_endline "trans1 (after)";
  Format.printf "%a\n" Print.term' prog;
  print_endline @@ Syntax.show_term prog;
  prog

let read_file filename = 
  let lines = ref [] in
  let chan = open_in filename in
  try
    while true; do
      lines := input_line chan :: !lines
    done; !lines
  with End_of_file ->
    close_in chan;
    List.rev !lines

let substitute_adhoc filenames (typ : [`Unit | `Int]) =
  match filenames with
  | [filename] -> begin
    let content = read_file filename |> String.concat "\n" in
    let re = Str.regexp "^ *let\\( \\|\\n\\|\\r\\)+\\(main\\)" in
    let content = Str.replace_first re "let \\2__" content in
    let content = content ^ "\nlet main () = assert (main__ () = " ^ (match typ with `Unit -> "()" | `Int -> "0") ^ ")\n" in
    let r = Random.int 0x10000000 in
    let file = Printf.sprintf "/tmp/%d.txt" r in
    let oc = open_out file in
    Printf.fprintf oc "%s" content;
    close_out oc;
    print_endline file;
    file
  end
  | _ -> failwith "substitute_adhoc"

let main filenames =
  (* let re = Str.regexp "\\(FAIL_[0-9]+\\( \\|\t\\|\r\\|\n\\|[a-z]\\|[A-Z]\\|_\\|[0-9]\\)+\\)=v\\( \\|\t\\|\r\\|\n\\)false\\." in
   Str.replace_first re "\\1=v true." "FAIL_498 u_499 k_500 =v false." in *)
  (* origにはdirectiveと型定義が入っている．今回は無視してよい *)
  let filename = substitute_adhoc !Flag.Input.filenames `Unit in
  let _, parsed =
    try
      Parser_wrapper.parse_files [filename]
    with _ ->
      let filename = substitute_adhoc !Flag.Input.filenames `Int in
      Parser_wrapper.parse_files [filename] in
  let parsed = trans1 parsed in
  let problem = Problem.safety parsed in
  Main_loop.run Spec.init problem

let () =
  Cmd.parse_arg ();
  save_input_to_file !Flag.Input.filenames;
  main !Flag.Input.filenames


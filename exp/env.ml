let limit = ref 120
let default_option () = Format.sprintf " -limit %d" !limit
let mochi () = "./mochi.opt -exp" ^ default_option ()
let wiki_dir = "wiki/"
let program_list = "program.list"
let option_list = "option.list"
let exp_list = "exp.list"

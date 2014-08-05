open Syntax


val flatten_tvar : typed_term -> typed_term
val inst_tvar_tunit : typed_term -> typed_term
val get_tvars : typ -> typ option ref list
val rename_poly_funs : id -> typed_term -> (id * id) list * typed_term
val copy_poly_funs : typed_term -> typed_term
val define_randvalue : (typ * id) list -> (id * id list * typed_term) list -> typ -> (typ * id) list * (id * id list * typed_term) list * typed_term
val inst_randval : typed_term -> typed_term
val get_last_definition : id option -> typed_term -> id option
val replace_main : typed_term -> typed_term -> typed_term
val set_target : typed_term -> string * int * typed_term
val merge_let_fun : typed_term -> typed_term
val canonize : typed_term -> typed_term
val part_eval : typed_term -> typed_term
val trans_let : typed_term -> typed_term
val propagate_typ_arg : typed_term -> typed_term
val replace_typ : (Syntax.id * Syntax.typ) list -> typed_term -> typed_term
val eval : typed_term -> typed_term
val beta_reduce : typed_term -> typed_term
val normalize_binop_exp : binop -> typed_term -> typed_term -> term
val normalize_bool_exp : typed_term -> typed_term
val get_and_list : typed_term -> typed_term list
val merge_geq_leq : typed_term -> typed_term
val elim_fun : typed_term -> typed_term
val make_ext_env : typed_term -> (id * typ) list
val init_rand_int : typed_term -> typed_term
val inlined_f : id list -> typed_term -> typed_term
val lift_fst_snd : typed_term -> typed_term
val expand_let_val : typed_term -> typed_term
val simplify_match : typed_term -> typed_term
val should_insert : typ list -> bool
val insert_param_funarg : typed_term -> typed_term
val search_fail : typed_term -> int list list
val screen_fail : int list -> typed_term -> typed_term
val rename_ext_funs : id list -> typed_term -> id list * typed_term
val make_ext_funs : typed_term -> typed_term
val assoc_typ : id -> typed_term -> typ
val let2fun : typed_term -> typed_term
val fun2let : typed_term -> typed_term
val beta_no_effect : typed_term -> typed_term
val diff_terms : typed_term -> typed_term -> (typed_term * typed_term) list
val subst_let_xy : typed_term -> typed_term
val flatten_let : typed_term -> typed_term
val normalize_let : typed_term -> typed_term
val remove_label : ?label:string option -> typed_term -> typed_term
val decomp_pair_eq : typed_term -> typed_term
val elim_unused_let : ?cbv:bool -> typed_term -> typed_term
val alpha_rename : typed_term -> typed_term
val elim_unused_branch : typed_term -> typed_term
val inline_no_effect : typed_term -> typed_term
val inline_var : typed_term -> typed_term
val inline_var_const : typed_term -> typed_term
val inline_simple_exp : typed_term -> typed_term
val replace_base_with_int : typed_term -> typed_term
val abst_ref : typed_term -> typed_term
val remove_top_por : typed_term -> typed_term
val short_circuit_eval : typed_term -> typed_term
val replace_bottom_def : typed_term -> typed_term
val flatten_tuple : typed_term -> typed_term
val inline_next_redex : typed_term -> typed_term
val beta_var_tuple : typed_term -> typed_term
val beta_no_effect_tuple : typed_term -> typed_term
val reduce_bottom : typed_term -> typed_term

let rec mc91 (prev_set_flag_mc91_37:bool) (s_prev_mc91_n_36:int) (n:int) =
  if prev_set_flag_mc91_37
  then
    if 111 + -s_prev_mc91_n_36 > 111 + -n && 111 + -n >= 0
    then
      ()
    else
      assert false;
  mc91_without_checking_45 prev_set_flag_mc91_37 s_prev_mc91_n_36 n
and mc91_without_checking_45 (_:bool) (_:int) (n:int) =
  let set_flag_mc91_38 = true
  in
  let s_mc91_n_35 = n
  in
  if n > 100
  then
    n - 10
  else
    mc91_without_checking_45
      set_flag_mc91_38 s_mc91_n_35
      (mc91_without_checking_45 set_flag_mc91_38 s_mc91_n_35 (n + 11))
and u_33 = mc91 false 0 (Random.int 0)
let u_2756 = ()
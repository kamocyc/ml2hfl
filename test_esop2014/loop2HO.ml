let id (u:unit) = u
let app (f:unit->unit->unit) (u:unit) = f u ()
let rec f m n (u:unit) =
let r = Random.int 0 in
if r > 0 && m > 0 then app (f (m-1) n)
else if r <= 0 && n > 0 then app (f m (n-1))
else id
let main (u:unit) = f (Random.int 0) (Random.int 0) ()
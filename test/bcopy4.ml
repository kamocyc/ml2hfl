
let array1 i = 0 in
let array2 i = 0 in
let update a i x j = if j=i then x else a j in

let rec bcopy_aux m src des i =
  if i >= m
  then ()
  else
    begin
      assert (0<=i && i<=m);
      let des = update des i (src i) in
        bcopy_aux m src des (i+1)
    end
in
let bcopy src des = bcopy_aux n src des 0 in
  bcopy array1 array2

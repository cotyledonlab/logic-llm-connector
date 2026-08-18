# Do not mutate Logic project packages directly

The connector will use Logic itself and documented interchange formats rather
than directly changing `.logicx` internals or depending on a reverse-engineered
Logic Remote protocol. Those mechanisms could increase apparent coverage but
have no stable published contract, making project corruption and silent
version breakage unacceptable foundations for trusted Operations.

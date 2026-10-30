// Training-only adapter for Scan 3.1; not linked into the App.
   if (arg == "samples") {
      bit::init();
      eval_init();
      std::mt19937 rng(481516);
      std::function<int(const Pos &)> quiet = [&](const Pos & p) {
         List captures; gen_captures(captures, p);
         if (captures.size() == 0) return int(eval(p));
         int best = -10000;
         for (Move m : captures) best = std::max(best, -quiet(p.succ(m)));
         return best;
      };
      int samples = 0;
      for (int game = 0; samples < 500000; ++game) {
         Pos p = pos::Start;
         for (int ply = 0; ply < 150; ++ply) {
            List moves; gen_moves(moves, p);
            if (moves.size() == 0 || bit::count(p.white()) == 0 || bit::count(p.black()) == 0) break;
            if (ply >= 8 && !can_capture(p, p.turn()) && p.king() == 0) {
               std::cout << pos_hub(p) << " " << int(eval(p)) * (p.turn() == White ? 1 : -1) << "\n";
               ++samples;
            }
            int selected = rng() % moves.size();
            if (ply >= 8 && rng() % 100 >= 25) {
               int best = -100000;
               for (int i = 0; i < moves.size(); ++i) {
                  int score = -quiet(p.succ(moves[i])) + int(rng() % 61) - 30;
                  if (score > best) { best = score; selected = i; }
               }
            }
            p = p.succ(moves[selected]);
         }
      }
      return 0;
   }


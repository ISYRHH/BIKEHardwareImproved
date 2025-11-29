-- Testbench for CombaMul
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY TB_CombaMul IS
END ENTITY;

ARCHITECTURE behavior OF TB_CombaMul IS
    CONSTANT WIDTH : NATURAL := 16;

    SIGNAL A_s : STD_LOGIC_VECTOR(WIDTH-1 DOWNTO 0) := (OTHERS=>'0');
    SIGNAL B_s : STD_LOGIC_VECTOR(WIDTH-1 DOWNTO 0) := (OTHERS=>'0');
    SIGNAL R_s : STD_LOGIC_VECTOR(2*WIDTH-2 DOWNTO 0);

    -- DUT
    COMPONENT CombaMul
        GENERIC (WIDTH : NATURAL := 32);
        PORT (A : IN STD_LOGIC_VECTOR(WIDTH-1 DOWNTO 0);
              B : IN STD_LOGIC_VECTOR(WIDTH-1 DOWNTO 0);
              R : OUT STD_LOGIC_VECTOR(2*WIDTH-2 DOWNTO 0));
    END COMPONENT;

    -- reference result
    SIGNAL R_ref : STD_LOGIC_VECTOR(2*WIDTH-2 DOWNTO 0);

    -- simple clock for pacing
    SIGNAL clk : STD_LOGIC := '0';

    -- test control
    SIGNAL errors : INTEGER := 0;

BEGIN
    DUT: CombaMul
        GENERIC MAP (WIDTH => WIDTH)
        PORT MAP (A => A_s, B => B_s, R => R_s);

    clk_proc: PROCESS
    BEGIN
        WAIT FOR 5 ns;
        clk <= NOT clk;
    END PROCESS;

    stim_proc: PROCESS
        VARIABLE a_int : unsigned(WIDTH-1 DOWNTO 0);
        VARIABLE b_int : unsigned(WIDTH-1 DOWNTO 0);
        VARIABLE tmp : unsigned(2*WIDTH-2 DOWNTO 0);
    BEGIN
        -- run multiple random tests
        FOR t IN 0 TO 200 LOOP
            -- simple pseudo-random generator
            a_int := to_unsigned((t*1103515245 + 12345) MOD 2**WIDTH, WIDTH);
            b_int := to_unsigned((t*22695477 + 1) MOD 2**WIDTH, WIDTH);
            A_s <= std_logic_vector(a_int);
            B_s <= std_logic_vector(b_int);
            WAIT FOR 20 ns;

            -- compute reference carry-less product
            tmp := (OTHERS => '0');
            FOR i IN 0 TO WIDTH-1 LOOP
                IF a_int(i) = '1' THEN
                    FOR j IN 0 TO WIDTH-1 LOOP
                        IF b_int(j) = '1' THEN
                            tmp(i+j) := not tmp(i+j);
                        END IF;
                    END LOOP;
                END IF;
            END LOOP;
            R_ref <= std_logic_vector(tmp);
            WAIT FOR 1 ns;

            IF R_s /= R_ref THEN
                report "Mismatch at test " & INTEGER'IMAGE(t) severity warning;
                errors <= errors + 1;
            END IF;
        END LOOP;

        IF errors = 0 THEN
            report "All CombaMul tests passed" severity note;
        ELSE
            report INTEGER'IMAGE(errors) & " errors found" severity error;
        END IF;

        WAIT;
    END PROCESS;

END ARCHITECTURE;

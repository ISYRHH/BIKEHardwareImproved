-- Testbench for CombaTop
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY TB_CombaTop IS
END ENTITY;

ARCHITECTURE behavior OF TB_CombaTop IS
    CONSTANT WORDS : NATURAL := 4;
    CONSTANT BW    : NATURAL := 8;

    SIGNAL clk : STD_LOGIC := '0';
    SIGNAL rst : STD_LOGIC := '1';

    SIGNAL A_LOAD_EN : STD_LOGIC := '0';
    SIGNAL A_LOAD_ADDR : STD_LOGIC_VECTOR( integer(ceil(log2(real(WORDS)))) - 1 DOWNTO 0) := (OTHERS=>'0');
    SIGNAL A_LOAD_DATA : STD_LOGIC_VECTOR(BW-1 DOWNTO 0) := (OTHERS=>'0');

    SIGNAL B_LOAD_EN : STD_LOGIC := '0';
    SIGNAL B_LOAD_ADDR : STD_LOGIC_VECTOR( integer(ceil(log2(real(WORDS)))) - 1 DOWNTO 0) := (OTHERS=>'0');
    SIGNAL B_LOAD_DATA : STD_LOGIC_VECTOR(BW-1 DOWNTO 0) := (OTHERS=>'0');

    SIGNAL START : STD_LOGIC := '0';
    SIGNAL DONE  : STD_LOGIC;

    SIGNAL RESULT_WORD_OUT  : STD_LOGIC_VECTOR(BW-1 DOWNTO 0);
    SIGNAL RESULT_WORD_ADDR : STD_LOGIC_VECTOR( integer(ceil(log2(real(2*WORDS)))) - 1 DOWNTO 0);
    SIGNAL RESULT_WORD_VALID: STD_LOGIC;

    -- reference arrays
    TYPE mem_t IS ARRAY(0 TO WORDS-1) OF STD_LOGIC_VECTOR(BW-1 DOWNTO 0);
    SIGNAL A_ref, B_ref : mem_t := (OTHERS => (OTHERS => '0'));

    SIGNAL errors : INTEGER := 0;

BEGIN
    UUT: ENTITY work.CombaTop
        GENERIC MAP (WORDS => WORDS, BW => BW)
        PORT MAP (
            CLK => clk,
            RESET => rst,
            A_LOAD_EN => A_LOAD_EN,
            A_LOAD_ADDR => A_LOAD_ADDR,
            A_LOAD_DATA => A_LOAD_DATA,
            B_LOAD_EN => B_LOAD_EN,
            B_LOAD_ADDR => B_LOAD_ADDR,
            B_LOAD_DATA => B_LOAD_DATA,
            START => START,
            DONE => DONE,
            RESULT_WORD_OUT => RESULT_WORD_OUT,
            RESULT_WORD_ADDR => RESULT_WORD_ADDR,
            RESULT_WORD_VALID => RESULT_WORD_VALID
        );

    clk_proc: PROCESS
    BEGIN
        WAIT FOR 5 ns;
        clk <= NOT clk;
    END PROCESS;

    stim: PROCESS
        VARIABLE a_int : unsigned(BW-1 DOWNTO 0);
        VARIABLE b_int : unsigned(BW-1 DOWNTO 0);
        VARIABLE full_ref : STD_LOGIC_VECTOR(2*WORDS*BW-1 DOWNTO 0);
        VARIABLE tmp : STD_LOGIC_VECTOR(2*BW-2 DOWNTO 0);
    BEGIN
        -- reset
        rst <= '1';
        WAIT FOR 20 ns;
        rst <= '0';

        -- load small deterministic operands
        FOR i IN 0 TO WORDS-1 LOOP
            a_int := to_unsigned(i*37 + 13, BW);
            b_int := to_unsigned(i*19 + 7, BW);
            A_ref(i) <= std_logic_vector(a_int);
            B_ref(i) <= std_logic_vector(b_int);

            A_LOAD_ADDR <= std_logic_vector(to_unsigned(i, A_LOAD_ADDR'length));
            A_LOAD_DATA <= std_logic_vector(a_int);
            A_LOAD_EN <= '1';
            WAIT FOR 10 ns;
            A_LOAD_EN <= '0';

            B_LOAD_ADDR <= std_logic_vector(to_unsigned(i, B_LOAD_ADDR'length));
            B_LOAD_DATA <= std_logic_vector(b_int);
            B_LOAD_EN <= '1';
            WAIT FOR 10 ns;
            B_LOAD_EN <= '0';
        END LOOP;

        -- compute reference full result (bit-level carry-less)
        full_ref := (OTHERS => '0');
        FOR i IN 0 TO WORDS-1 LOOP
            FOR j IN 0 TO WORDS-1 LOOP
                tmp := (OTHERS => '0');
                -- compute partial
                FOR bi IN 0 TO BW-1 LOOP
                    FOR bj IN 0 TO BW-1 LOOP
                        IF A_ref(i)(bi) = '1' AND B_ref(j)(bj) = '1' THEN
                            -- toggle bit at position (i*BW + j*BW + bi + bj)
                            full_ref( (i+j)*BW + bi + bj ) := not full_ref( (i+j)*BW + bi + bj );
                        END IF;
                    END LOOP;
                END LOOP;
            END LOOP;
        END LOOP;

        -- start UUT
        START <= '1';
        WAIT FOR 10 ns;
        START <= '0';

        -- collect streamed results and compare
        FOR r IN 0 TO 2*WORDS-1 LOOP
            WAIT UNTIL RESULT_WORD_VALID = '1';
            -- compare the word
            IF RESULT_WORD_OUT /= full_ref( r*BW + BW-1 DOWNTO r*BW ) THEN
                report "Mismatch at word " & INTEGER'IMAGE(r) severity warning;
                errors <= errors + 1;
            END IF;
            WAIT FOR 1 ns;
        END LOOP;

        IF errors = 0 THEN
            report "CombaTop TB passed" severity note;
        ELSE
            report INTEGER'IMAGE(errors) & " errors" severity error;
        END IF;

        WAIT;
    END PROCESS;

END ARCHITECTURE;

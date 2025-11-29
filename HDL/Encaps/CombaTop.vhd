----------------------------------------------------------------------------------
-- CombaTop: digit-serial top using CombaMul leaf
-- - Load operands by writing words into A/B memories via load ports
-- - Start computation by asserting START
-- - Outputs result words via RESULT_WORD_OUT/RESULT_WORD_ADDR with RESULT_WORD_VALID pulses
-- Generic parameters: WORDS (number of words per operand), BW (bits per word)
----------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE IEEE.MATH_REAL.ALL;

ENTITY CombaTop IS
    GENERIC (
        WORDS : NATURAL := 4;
        BW    : NATURAL := 8
    );
    PORT (
        CLK      : IN  STD_LOGIC;
        RESET    : IN  STD_LOGIC;

        -- Load interfaces for operand A
        A_LOAD_EN   : IN  STD_LOGIC;
        A_LOAD_ADDR : IN  STD_LOGIC_VECTOR( integer(ceil(log2(real(WORDS)))) - 1 DOWNTO 0 );
        A_LOAD_DATA : IN  STD_LOGIC_VECTOR(BW-1 DOWNTO 0);

        -- Load interfaces for operand B
        B_LOAD_EN   : IN  STD_LOGIC;
        B_LOAD_ADDR : IN  STD_LOGIC_VECTOR( integer(ceil(log2(real(WORDS)))) - 1 DOWNTO 0 );
        B_LOAD_DATA : IN  STD_LOGIC_VECTOR(BW-1 DOWNTO 0);

        -- Control
        START    : IN  STD_LOGIC;
        DONE     : OUT STD_LOGIC;

        -- Result streaming
        RESULT_WORD_OUT  : OUT STD_LOGIC_VECTOR(BW-1 DOWNTO 0);
        RESULT_WORD_ADDR : OUT STD_LOGIC_VECTOR( integer(ceil(log2(real(2*WORDS)))) - 1 DOWNTO 0 );
        RESULT_WORD_VALID: OUT STD_LOGIC
    );
END ENTITY;

ARCHITECTURE rtl OF CombaTop IS
    -- local constants
    CONSTANT RES_WORDS : NATURAL := 2*WORDS;
    CONSTANT RES_BITS  : NATURAL := RES_WORDS * BW;

    -- types
    TYPE mem_t IS ARRAY(0 TO WORDS-1) OF STD_LOGIC_VECTOR(BW-1 DOWNTO 0);

    -- memories
    SIGNAL A_mem : mem_t := (OTHERS => (OTHERS => '0'));
    SIGNAL B_mem : mem_t := (OTHERS => (OTHERS => '0'));

    -- computation indices
    SIGNAL i_idx, j_idx : INTEGER RANGE 0 TO WORDS := 0;

    -- accumulation vector
    SIGNAL full_res : STD_LOGIC_VECTOR(RES_BITS-1 DOWNTO 0) := (OTHERS => '0');

    -- Comba leaf signals
    SIGNAL COMBA_A : STD_LOGIC_VECTOR(BW-1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL COMBA_B : STD_LOGIC_VECTOR(BW-1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL COMBA_R : STD_LOGIC_VECTOR(2*BW-2 DOWNTO 0);

    -- FSM
    TYPE state_t IS (S_IDLE, S_COMPUTE, S_WRITE, S_DONE);
    SIGNAL state : state_t := S_IDLE;

    -- write pointer
    SIGNAL wr_ptr : INTEGER RANGE 0 TO RES_WORDS := 0;

BEGIN
    -- instantiate single Comba leaf
    COMBA_LEAF: ENTITY work.CombaMul
        GENERIC MAP (WIDTH => BW)
        PORT MAP (A => COMBA_A, B => COMBA_B, R => COMBA_R);

    -- load ports (synchronous write)
    LOAD_PROC: PROCESS(CLK)
    BEGIN
        IF RISING_EDGE(CLK) THEN
            IF RESET = '1' THEN
                A_mem <= (OTHERS => (OTHERS => '0'));
                B_mem <= (OTHERS => (OTHERS => '0'));
            ELSE
                IF A_LOAD_EN = '1' THEN
                    A_mem( TO_INTEGER(unsigned(A_LOAD_ADDR)) ) <= A_LOAD_DATA;
                END IF;
                IF B_LOAD_EN = '1' THEN
                    B_mem( TO_INTEGER(unsigned(B_LOAD_ADDR)) ) <= B_LOAD_DATA;
                END IF;
            END IF;
        END IF;
    END PROCESS;

    -- main FSM for multiplication
    MAIN: PROCESS(CLK)
        VARIABLE base_pos : INTEGER;
        VARIABLE p_len    : INTEGER := 2*BW-1;
    BEGIN
        IF RISING_EDGE(CLK) THEN
            IF RESET = '1' THEN
                state <= S_IDLE;
                i_idx <= 0; j_idx <= 0;
                full_res <= (OTHERS => '0');
                DONE <= '0';
                RESULT_WORD_VALID <= '0';
                wr_ptr <= 0;
            ELSE
                CASE state IS
                    WHEN S_IDLE =>
                        DONE <= '0';
                        RESULT_WORD_VALID <= '0';
                        IF START = '1' THEN
                            -- reset accumulators
                            full_res <= (OTHERS => '0');
                            i_idx <= 0; j_idx <= 0;
                            state <= S_COMPUTE;
                        END IF;

                    WHEN S_COMPUTE =>
                        -- set leaf inputs
                        COMBA_A <= A_mem(i_idx);
                        COMBA_B <= B_mem(j_idx);
                        -- after combinational leaf available (same cycle), accumulate
                        base_pos := (i_idx + j_idx) * BW;
                        -- XOR COMBA_R into full_res at base_pos
                        FOR k IN 0 TO p_len-1 LOOP
                            IF COMBA_R(k) = '1' THEN
                                full_res(base_pos + k) <= not full_res(base_pos + k);
                            END IF;
                        END LOOP;

                        -- advance indices
                        IF j_idx = WORDS-1 THEN
                            j_idx <= 0;
                            IF i_idx = WORDS-1 THEN
                                i_idx <= 0;
                                state <= S_WRITE;
                                wr_ptr <= 0;
                            ELSE
                                i_idx <= i_idx + 1;
                            END IF;
                        ELSE
                            j_idx <= j_idx + 1;
                        END IF;

                    WHEN S_WRITE =>
                        -- stream out result words
                        RESULT_WORD_OUT <= full_res( wr_ptr*BW + BW-1 DOWNTO wr_ptr*BW );
                        RESULT_WORD_ADDR <= std_logic_vector( to_unsigned(wr_ptr, RESULT_WORD_ADDR'length) );
                        RESULT_WORD_VALID <= '1';
                        IF wr_ptr = RES_WORDS-1 THEN
                            state <= S_DONE;
                        END IF;
                        wr_ptr <= wr_ptr + 1;

                    WHEN S_DONE =>
                        RESULT_WORD_VALID <= '0';
                        DONE <= '1';
                        state <= S_IDLE;

                END CASE;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE;

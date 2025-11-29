----------------------------------------------------------------------------------
-- COPYRIGHT (c) 2020 ALL RIGHT RESERVED
--
-- COMPANY:					Ruhr-University Bochum, Chair for Security Engineering
-- AUTHOR:					Jan Richter-Brockmann
--
-- CREATE DATE:			    03/02/2020
-- LAST CHANGES:            23/04/2020
-- MODULE NAME:			    BIKE_MULTIPLIER
--
-- REVISION:				1.10 - Adapted to BIKE-2.
--
-- LICENCE: 				Please look at licence.txt
-- USAGE INFORMATION:	    Please look at readme.txt. If licence.txt or readme.txt
--							are missing or	if you have questions regarding the code
--							please contact Tim G�neysu (tim.gueneysu@rub.de) and
--                          Jan Richter-Brockmann (jan.richter-brockmann@rub.de)
--
-- THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY 
-- KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
-- IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
-- PARTICULAR PURPOSE.
----------------------------------------------------------------------------------



-- IMPORTS
----------------------------------------------------------------------------------
LIBRARY IEEE;
    USE IEEE.STD_LOGIC_1164.ALL;
    USE IEEE.NUMERIC_STD.ALL;
    USE IEEE.MATH_REAL.ALL;

LIBRARY UNISIM;
    USE UNISIM.VCOMPONENTS.ALL;
    
LIBRARY work;
    USE work.BIKE_SETTINGS.ALL;



-- ENTITY
----------------------------------------------------------------------------------
ENTITY BIKE_MULTIPLIER IS
    GENERIC (
        USE_COMBA_TEST : BOOLEAN := false
    );
    PORT (  
        CLK                 : IN  STD_LOGIC;
        -- CONTROL PORTS ---------------	
        RESET               : IN  STD_LOGIC;
        ENABLE              : IN  STD_LOGIC;
        DONE                : OUT STD_LOGIC;
        -- RESULT ----------------------
        RESULT_RDEN         : OUT STD_LOGIC;
        RESULT_WREN         : OUT STD_LOGIC;
        RESULT_ADDR         : OUT STD_LOGIC_VECTOR(LOG2(WORDS)-1 DOWNTO 0);
        RESULT_DOUT_0       : OUT STD_LOGIC_VECTOR(B_WIDTH-1 DOWNTO 0);
        RESULT_DIN_0        : IN  STD_LOGIC_VECTOR(B_WIDTH-1 DOWNTO 0);
        -- KEY -------------------------
        K_RDEN              : OUT STD_LOGIC;
        K_WREN              : OUT STD_LOGIC;
        K_ADDR              : OUT STD_LOGIC_VECTOR(LOG2(WORDS)-1 DOWNTO 0);
        K_DOUT_0            : OUT STD_LOGIC_VECTOR(B_WIDTH-1 DOWNTO 0);
        K_DIN_0             : IN  STD_LOGIC_VECTOR(B_WIDTH-1 DOWNTO 0);
        -- MESSAGE ---------------------
        M_RDEN              : OUT STD_LOGIC;
        M_ADDR              : OUT STD_LOGIC_VECTOR(LOG2(WORDS)-1 DOWNTO 0);
        M_DIN               : IN  STD_LOGIC_VECTOR(B_WIDTH-1 DOWNTO 0)   
    );
END BIKE_MULTIPLIER;



-- ARCHITECTURE
----------------------------------------------------------------------------------
ARCHITECTURE Behavioral OF BIKE_MULTIPLIER IS

    -- Optional Comba leaf multiplier component (for testing / replacement)
    COMPONENT CombaMul
        GENERIC (WIDTH : NATURAL := 32);
        PORT (
            A : IN STD_LOGIC_VECTOR(WIDTH-1 DOWNTO 0);
            B : IN STD_LOGIC_VECTOR(WIDTH-1 DOWNTO 0);
            R : OUT STD_LOGIC_VECTOR(2*WIDTH-2 DOWNTO 0)
        );
    END COMPONENT;

    -- Result of the optional Comba leaf (2*B_WIDTH-1 bits)
    SIGNAL RESULT_COMBA : STD_LOGIC_VECTOR(2*B_WIDTH-2 DOWNTO 0);



-- CONSTANTS ---------------------------------------------------------------------
CONSTANT WORDS      : NATURAL := CEIL(R_BITS, B_WIDTH);
CONSTANT OVERHANG   : NATURAL := R_BITS - B_WIDTH*(WORDS-1);



-- SIGNALS
----------------------------------------------------------------------------------
-- CONTROL
SIGNAL WRITE_LAST                               : STD_LOGIC;
SIGNAL WRITE_FRAC                               : STD_LOGIC;
SIGNAL SEL_LOW, SEL_LOW_D                       : STD_LOGIC_VECTOR(1 DOWNTO 0);

-- COUNTER
SIGNAL CNT_ROW_EN, CNT_ROW_RST                  : STD_LOGIC;   
SIGNAL CNT_COL_EN, CNT_COL_RST                  : STD_LOGIC;   
SIGNAL CNT_SHIFT_EN, CNT_SHIFT_RST              : STD_LOGIC;   
SIGNAL CNT_ROW_OUT, CNT_COL_OUT, CNT_SHIFT_OUT  : STD_LOGIC_VECTOR(LOG2(WORDS)-1 DOWNTO 0);

-- KEY 
SIGNAL K_ADDR_INT                               : STD_LOGIC_VECTOR(LOG2(WORDS)-1 DOWNTO 0);
SIGNAL K_KEY0_MSBS_D, K_KEY1_MSBS_D             : STD_LOGIC_VECTOR(B_WIDTH-OVERHANG-1 DOWNTO 0);

-- INTERMEDIATE REGISTER
SIGNAL INT_IN_0, INT_OUT_0                      : STD_LOGIC_VECTOR(B_WIDTH-2 DOWNTO 0);

-- SYSTOLIC MULTIPLIER
SIGNAL RESULT_SUBARRAY_0                        : STD_LOGIC_VECTOR(B_WIDTH*B_WIDTH-1 DOWNTO 0);
SIGNAL RESULT_UPPER_SUBARRAY_REORDERED_0        : STD_LOGIC_VECTOR(B_WIDTH*(B_WIDTH+1)/2-1 DOWNTO 0);
SIGNAL RESULT_LOWER_SUBARRAY_REORDERED_0        : STD_LOGIC_VECTOR((B_WIDTH-1)*(B_WIDTH)/2-1 DOWNTO 0);
SIGNAL RESULT_LOWER_SUBARRAY_REORDERED_INIT1_0  : STD_LOGIC_VECTOR((B_WIDTH-1)*(B_WIDTH)/2-1 DOWNTO 0) := (OTHERS => '0');
SIGNAL RESULT_LOWER_SUBARRAY_REORDERED_INIT2_0  : STD_LOGIC_VECTOR((B_WIDTH-1)*(B_WIDTH)/2-1 DOWNTO 0) := (OTHERS => '0');
SIGNAL RESULT_TRAPEZOIDAL_UPPER_ADDITION_0      : STD_LOGIC_VECTOR(B_WIDTH-1 DOWNTO 0);
SIGNAL RESULT_UPPER_INT_ADD_0                   : STD_LOGIC_VECTOR(B_WIDTH*(B_WIDTH+1)/2-1 DOWNTO 0); 
SIGNAL RESULT_LOWER_SUBARRAY_ADD_IN_0           : STD_LOGIC_VECTOR((B_WIDTH-1)*(B_WIDTH)/2-1 DOWNTO 0);
SIGNAL RESULT_TRAPEZOIDAL_LOWER_ADDITION_0      : STD_LOGIC_VECTOR(B_WIDTH-2 DOWNTO 0);
SIGNAL RESULT_LOWER_INT_ADD_0                   : STD_LOGIC_VECTOR((B_WIDTH-1)*(B_WIDTH)/2-1 DOWNTO 0);
SIGNAL RESULT_DOUT_ADD_0                        : STD_LOGIC_VECTOR(B_WIDTH-1 DOWNTO 0);



-- STATES
----------------------------------------------------------------------------------
TYPE STATES IS (S_RESET, S_READ_SECOND_LAST, S_READ_LAST, S_FIRST_COLUMN, S_COLUMN, S_SWITCH_COLUMN, S_WRITE_LAST, S_DONE);
SIGNAL STATE : STATES := S_RESET;



-- BEHAVIORAL
----------------------------------------------------------------------------------
BEGIN

    -- Test / replacement: instantiate a CombaTop when enabled
    -- Signals for CombaTop instance (only used in test mode)
    SIGNAL CT_A_LOAD_EN   : STD_LOGIC := '0';
    SIGNAL CT_A_LOAD_ADDR : STD_LOGIC_VECTOR(LOG2(WORDS)-1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL CT_A_LOAD_DATA : STD_LOGIC_VECTOR(B_WIDTH-1 DOWNTO 0) := (OTHERS => '0');

    SIGNAL CT_B_LOAD_EN   : STD_LOGIC := '0';
    SIGNAL CT_B_LOAD_ADDR : STD_LOGIC_VECTOR(LOG2(WORDS)-1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL CT_B_LOAD_DATA : STD_LOGIC_VECTOR(B_WIDTH-1 DOWNTO 0) := (OTHERS => '0');

    SIGNAL CT_START       : STD_LOGIC := '0';
    SIGNAL CT_DONE_SIG    : STD_LOGIC;

    SIGNAL CT_RES_OUT     : STD_LOGIC_VECTOR(B_WIDTH-1 DOWNTO 0);
    SIGNAL CT_RES_ADDR    : STD_LOGIC_VECTOR(LOG2(WORDS) DOWNTO 0); -- needs +1 bit for 2*WORDS
    SIGNAL CT_RES_VALID   : STD_LOGIC := '0';

    COMBATOP_GEN : IF USE_COMBA_TEST GENERATE
        -- FINITE STATE MACHINE PROCESS ----------------------------------------------
        NO_TEST_GEN : IF NOT USE_COMBA_TEST GENERATE
            FSM : PROCESS(CLK)
            BEGIN
                IF RISING_EDGE(CLK) THEN
                    IF RESET = '1' THEN
                        STATE <= S_RESET;
                    
                        -- GLOBAL ----------
                        DONE            <= '0';
                    
                        -- CONTROL ---------
                        SEL_LOW         <= "00";
                        WRITE_LAST      <= '0';

                        -- KEY -------------
                        K_RDEN          <= '0';                   
                        K_WREN          <= '0';   
                    
                        -- ERROR -----------
                        RESULT_RDEN     <= '0';
                        RESULT_WREN     <= '0'; 
                    
                        -- MESSAGE ---------
                        M_RDEN          <= '0';
                                        
                        -- COUNTER ---------
                        CNT_ROW_EN      <= '0';
                        CNT_ROW_RST     <= '1';
                    
                        CNT_COL_EN      <= '0';
                        CNT_COL_RST     <= '1';

                        CNT_SHIFT_EN    <= '0';
                        CNT_SHIFT_RST   <= '1';  
                    ELSE
                        CASE STATE IS
                        
                            ----------------------------------------------
                            WHEN S_RESET                =>
                                -- GLOBAL ----------
                                DONE            <= '0';
                            
                                -- CONTROL ---------
                                SEL_LOW         <= "00";
                                WRITE_LAST      <= '0';
    
                                -- KEY -------------
                                K_RDEN          <= '0';                   
                                K_WREN          <= '0';   
                            
                                -- ERROR -----------
                                RESULT_RDEN     <= '0';
                                RESULT_WREN     <= '0'; 
                            
                                -- MESSAGE ---------
                                M_RDEN          <= '0';
                                                
                                -- COUNTER ---------
                                CNT_ROW_EN      <= '0';
                                CNT_ROW_RST     <= '1';
                            
                                CNT_COL_EN      <= '0';
                                CNT_COL_RST     <= '1';
         
                                CNT_SHIFT_EN    <= '0';
                                CNT_SHIFT_RST   <= '1';               
                            
                                -- TRANSITION ------
                                IF (ENABLE = '1') THEN
                                    STATE       <= S_READ_SECOND_LAST;
                                ELSE
                                    STATE       <= S_RESET;
                                END IF;
                            ----------------------------------------------
                                        
                            ----------------------------------------------
                            WHEN S_READ_SECOND_LAST     =>
                                -- GLOBAL ----------
                                DONE            <= '0';
                            
                                -- CONTROL ---------
                                SEL_LOW         <= "01";
                                WRITE_LAST      <= '0';
    
                                -- KEY -------------
                                K_RDEN          <= '1';                  
                                K_WREN          <= '0';   
                            
                                -- ERROR -----------
                                RESULT_RDEN     <= '0';
                                RESULT_WREN     <= '0'; 
                            
                                -- MESSAGE ---------
                                M_RDEN          <= '1';
                                                
                                -- COUNTER ---------
                                CNT_ROW_EN      <= '0';
                                CNT_ROW_RST     <= '0';
                            
                                CNT_COL_EN      <= '0';
                                CNT_COL_RST     <= '0';
         
                                CNT_SHIFT_EN    <= '0';
                                CNT_SHIFT_RST   <= '0';               
                            
                                -- TRANSITION ------
                                STATE           <= S_READ_LAST;
                            ----------------------------------------------                
                        
                            ----------------------------------------------
                            WHEN S_READ_LAST            =>
                                -- GLOBAL ----------
                                DONE            <= '0';
                            
                                -- CONTROL ---------
                                SEL_LOW         <= "10";
                                WRITE_LAST      <= '0';
    
                                -- KEY -------------
                                K_RDEN          <= '1';                  
                                K_WREN          <= '0';   
                            
                                -- ERROR -----------
                                RESULT_RDEN     <= '0';
                                RESULT_WREN     <= '0'; 
                            
                                -- MESSAGE ---------
                                M_RDEN          <= '1';
                                                
                                -- COUNTER ---------
                                CNT_ROW_EN      <= '0';
                                CNT_ROW_RST     <= '0';
                            
                                CNT_COL_EN      <= '0';
                                CNT_COL_RST     <= '0';
         
                                CNT_SHIFT_EN    <= '0';
                                CNT_SHIFT_RST   <= '0';               
                            
                                -- TRANSITION ------
                                STATE           <= S_FIRST_COLUMN;
                            ----------------------------------------------  
                        
                            ----------------------------------------------
                            WHEN S_FIRST_COLUMN         =>
                                -- GLOBAL ----------
                                DONE            <= '0';
                                WRITE_LAST      <= '0';
                            
                                -- CONTROL ---------
                                SEL_LOW         <= "11";
    
                                -- KEY -------------
                                K_RDEN          <= '1';                  
                                K_WREN          <= '0';   
                            
                                -- ERROR -----------
                                RESULT_RDEN     <= '1';
                                RESULT_WREN     <= '0'; 
                            
                                -- MESSAGE ---------
                                M_RDEN          <= '1';
                                                
                                -- COUNTER ---------
                                CNT_ROW_EN      <= '1';
                                CNT_ROW_RST     <= '0';
                            
                                CNT_COL_EN      <= '0';
                                CNT_COL_RST     <= '0';
         
                                CNT_SHIFT_EN    <= '1';
                                CNT_SHIFT_RST   <= '0';               
                            
                                -- TRANSITION ------
                                STATE           <= S_COLUMN;
                            ----------------------------------------------                                 
    
                            ----------------------------------------------
                            WHEN S_COLUMN               =>
                                -- GLOBAL ----------
                                DONE            <= '0';
                            
                                -- CONTROL ---------
                                SEL_LOW         <= "11";
                                WRITE_LAST      <= '0';
    
                                -- KEY -------------
                                K_RDEN          <= '1';                  
                                K_WREN          <= '1';   
                            
                                -- ERROR -----------
                                RESULT_RDEN     <= '1';
                                RESULT_WREN     <= '1'; 
                            
                                -- MESSAGE ---------
                                M_RDEN          <= '1';
                                                
                                -- COUNTER ---------
                                CNT_ROW_EN      <= '1';
                                CNT_ROW_RST     <= '0';
                            
                                CNT_COL_EN      <= '0';
                                CNT_COL_RST     <= '0';
         
                                CNT_SHIFT_EN    <= '1';
                                CNT_SHIFT_RST   <= '0';               
                            
                                -- TRANSITION ------                    
                                IF (CNT_ROW_OUT = STD_LOGIC_VECTOR(TO_UNSIGNED(WORDS-2, LOG2(WORDS)))) THEN
                                    IF (CNT_COL_OUT = STD_LOGIC_VECTOR(TO_UNSIGNED(WORDS-1, LOG2(WORDS)))) THEN
                                        STATE           <= S_WRITE_LAST;
                                    ELSE
                                        STATE           <= S_SWITCH_COLUMN;
                                    END IF;
                                ELSE
                                    STATE               <= S_COLUMN;
                                END IF;                    
                            ---------------------------------------------- 
                        
                            ----------------------------------------------
                            WHEN S_SWITCH_COLUMN        =>
                                -- GLOBAL ----------
                                DONE            <= '0';
                            
                                -- CONTROL ---------
                                SEL_LOW         <= "11";
                                WRITE_LAST      <= '1';
    
                                -- KEY -------------
                                K_RDEN          <= '1';                  
                                K_WREN          <= '1';   
                            
                                -- ERROR -----------
                                RESULT_RDEN     <= '1';
                                RESULT_WREN     <= '1'; 
                            
                                -- MESSAGE ---------
                                M_RDEN          <= '1';
                                                
                                -- COUNTER ---------
                                CNT_ROW_EN      <= '0';
                                CNT_ROW_RST     <= '1';
                            
                                CNT_COL_EN      <= '1';
                                CNT_COL_RST     <= '0';
         
                                CNT_SHIFT_EN    <= '1';
                                CNT_SHIFT_RST   <= '0';               
                            
                                -- TRANSITION ----
                                STATE           <= S_READ_SECOND_LAST;                   
                            ---------------------------------------------- 
    
                            ----------------------------------------------
                            WHEN S_WRITE_LAST        =>
                                -- GLOBAL ----------
                                DONE            <= '0';
                            
                                -- CONTROL ---------
                                SEL_LOW         <= "11";
                                WRITE_LAST      <= '1';
    
                                -- KEY -------------
                                K_RDEN          <= '0';                  
                                K_WREN          <= '0';   
                            
                                -- ERROR -----------
                                RESULT_RDEN     <= '1';
                                RESULT_WREN     <= '1'; 
                            
                                -- MESSAGE ---------
                                M_RDEN          <= '0';
                                                
                                -- COUNTER ---------
                                CNT_ROW_EN      <= '0';
                                CNT_ROW_RST     <= '1';
                            
                                CNT_COL_EN      <= '0';
                                CNT_COL_RST     <= '0';
         
                                CNT_SHIFT_EN    <= '0';
                                CNT_SHIFT_RST   <= '0';               
                            
                                -- TRANSITION ----
                                STATE           <= S_DONE;                   
                            ---------------------------------------------- 
                                                            
                            ----------------------------------------------
                            WHEN S_DONE         =>   
                                -- GLOBAL ----------
                                DONE            <= '1';
                            
                                -- PRIVATE KEY -----
                                K_RDEN          <= '0';
                                K_WREN          <= '0';
    
                                -- ERROR -----------
                                RESULT_RDEN     <= '0';
                                RESULT_WREN     <= '0';
    
                                -- MESSAGE ---------
                                M_RDEN          <= '0';                
                            
                                CNT_ROW_EN      <= '0';
                                CNT_ROW_RST     <= '1';
    
                                CNT_COL_EN      <= '0';
                                CNT_COL_RST     <= '1';
                                                
                                CNT_SHIFT_EN    <= '0';
                                CNT_SHIFT_RST   <= '1';                            
                                 
                                -- TRANSITION ----
                                STATE           <= S_RESET;
                            ----------------------------------------------
                                        
                        END CASE;
                    END IF;
                END IF;
            END PROCESS;
        END GENERATE NO_TEST_GEN;

        TEST_GEN : IF USE_COMBA_TEST GENERATE
            -- Simple test FSM that loads K and M words, starts CombaTop and streams results
            TYPE TEST_STATES IS (T_IDLE, T_ADDR, T_CAPTURE, T_RUN, T_STREAM, T_DONE);
            SIGNAL T_STATE : TEST_STATES := T_IDLE;
            SIGNAL t_cnt   : INTEGER RANGE 0 TO WORDS := 0;
            SIGNAL addr_phase : STD_LOGIC := '0'; -- 0: issue addr+rden, 1: capture data

            FSM_TEST : PROCESS(CLK)
            BEGIN
                IF RISING_EDGE(CLK) THEN
                    IF RESET = '1' THEN
                        -- clear outputs and control
                        K_RDEN <= '0'; K_WREN <= '0'; K_ADDR <= (OTHERS => '0'); K_DOUT_0 <= (OTHERS => '0');
                        M_RDEN <= '0'; M_ADDR <= (OTHERS => '0');
                        RESULT_RDEN <= '0'; RESULT_WREN <= '0'; RESULT_ADDR <= (OTHERS => '0'); RESULT_DOUT_0 <= (OTHERS => '0');
                        CT_A_LOAD_EN <= '0'; CT_B_LOAD_EN <= '0'; CT_START <= '0';
                        DONE <= '0';
                        T_STATE <= T_IDLE; t_cnt <= 0; addr_phase <= '0';
                    ELSE
                        -- default deasserts
                        CT_A_LOAD_EN <= '0'; CT_B_LOAD_EN <= '0'; CT_START <= '0';
                        RESULT_WREN <= '0'; RESULT_RDEN <= '0';
                        CASE T_STATE IS
                            WHEN T_IDLE =>
                                DONE <= '0';
                                t_cnt <= 0; addr_phase <= '0';
                                -- wait for ENABLE to start test-mode multiplication
                                IF ENABLE = '1' THEN
                                    T_STATE <= T_ADDR;
                                END IF;

                            WHEN T_ADDR =>
                                -- issue addresses and read-enable to external memories
                                K_ADDR <= STD_LOGIC_VECTOR(TO_UNSIGNED(t_cnt, K_ADDR'length));
                                M_ADDR <= STD_LOGIC_VECTOR(TO_UNSIGNED(t_cnt, M_ADDR'length));
                                K_RDEN <= '1';
                                M_RDEN <= '1';
                                addr_phase <= '1';
                                T_STATE <= T_CAPTURE;

                            WHEN T_CAPTURE =>
                                -- capture returned data from external memories into CombaTop
                                K_RDEN <= '0'; M_RDEN <= '0';
                                CT_A_LOAD_ADDR <= K_ADDR;
                                CT_A_LOAD_DATA <= K_DIN_0;
                                CT_A_LOAD_EN <= '1';
                                CT_B_LOAD_ADDR <= M_ADDR;
                                CT_B_LOAD_DATA <= M_DIN;
                                CT_B_LOAD_EN <= '1';
                                -- advance count
                                IF t_cnt = WORDS-1 THEN
                                    t_cnt <= 0;
                                    T_STATE <= T_RUN;
                                ELSE
                                    t_cnt <= t_cnt + 1;
                                    T_STATE <= T_ADDR;
                                END IF;

                            WHEN T_RUN =>
                                -- start CombaTop
                                CT_START <= '1';
                                T_STATE <= T_STREAM;

                            WHEN T_STREAM =>
                                -- wait for result valid and stream to RESULT ports
                                IF CT_RES_VALID = '1' THEN
                                    RESULT_WREN <= '1';
                                    -- map CT_RES_ADDR down to RESULT_ADDR width (drop MSB if present)
                                    RESULT_ADDR <= CT_RES_ADDR(LOG2(WORDS)-1 DOWNTO 0);
                                    RESULT_DOUT_0 <= CT_RES_OUT;
                                ELSE
                                    RESULT_WREN <= '0';
                                END IF;
                                IF CT_DONE_SIG = '1' THEN
                                    T_STATE <= T_DONE;
                                END IF;

                            WHEN T_DONE =>
                                DONE <= '1';
                                T_STATE <= T_IDLE;

                        END CASE;
                    END IF;
                END IF;
            END PROCESS FSM_TEST;
        END GENERATE TEST_GEN;

        ------------------------------------------------------------------------------

    END Behavioral;
                        
                        -- MESSAGE ---------
                        M_RDEN          <= '1';
                                            
                        -- COUNTER ---------
                        CNT_ROW_EN      <= '1';
                        CNT_ROW_RST     <= '0';
                        
                        CNT_COL_EN      <= '0';
                        CNT_COL_RST     <= '0';
     
                        CNT_SHIFT_EN    <= '1';
                        CNT_SHIFT_RST   <= '0';               
                        
                        -- TRANSITION ------
                        STATE           <= S_COLUMN;
                    ----------------------------------------------                                  
    
                    ----------------------------------------------
                    WHEN S_COLUMN               =>
                        -- GLOBAL ----------
                        DONE            <= '0';
                        
                        -- CONTROL ---------
                        SEL_LOW         <= "11";
                        WRITE_LAST      <= '0';
    
                        -- KEY -------------
                        K_RDEN          <= '1';                  
                        K_WREN          <= '1';   
                        
                        -- ERROR -----------
                        RESULT_RDEN     <= '1';
                        RESULT_WREN     <= '1'; 
                        
                        -- MESSAGE ---------
                        M_RDEN          <= '1';
                                            
                        -- COUNTER ---------
                        CNT_ROW_EN      <= '1';
                        CNT_ROW_RST     <= '0';
                        
                        CNT_COL_EN      <= '0';
                        CNT_COL_RST     <= '0';
     
                        CNT_SHIFT_EN    <= '1';
                        CNT_SHIFT_RST   <= '0';               
                        
                        -- TRANSITION ------                    
                        IF (CNT_ROW_OUT = STD_LOGIC_VECTOR(TO_UNSIGNED(WORDS-2, LOG2(WORDS)))) THEN
                            IF (CNT_COL_OUT = STD_LOGIC_VECTOR(TO_UNSIGNED(WORDS-1, LOG2(WORDS)))) THEN
                                STATE           <= S_WRITE_LAST;
                            ELSE
                                STATE           <= S_SWITCH_COLUMN;
                            END IF;
                        ELSE
                            STATE               <= S_COLUMN;
                        END IF;                    
                    ---------------------------------------------- 
                    
                    ----------------------------------------------
                    WHEN S_SWITCH_COLUMN        =>
                        -- GLOBAL ----------
                        DONE            <= '0';
                        
                        -- CONTROL ---------
                        SEL_LOW         <= "11";
                        WRITE_LAST      <= '1';
    
                        -- KEY -------------
                        K_RDEN          <= '1';                  
                        K_WREN          <= '1';   
                        
                        -- ERROR -----------
                        RESULT_RDEN     <= '1';
                        RESULT_WREN     <= '1'; 
                        
                        -- MESSAGE ---------
                        M_RDEN          <= '1';
                                            
                        -- COUNTER ---------
                        CNT_ROW_EN      <= '0';
                        CNT_ROW_RST     <= '1';
                        
                        CNT_COL_EN      <= '1';
                        CNT_COL_RST     <= '0';
     
                        CNT_SHIFT_EN    <= '1';
                        CNT_SHIFT_RST   <= '0';               
                        
                        -- TRANSITION ------
                        STATE           <= S_READ_SECOND_LAST;                   
                    ---------------------------------------------- 
    
                    ----------------------------------------------
                    WHEN S_WRITE_LAST        =>
                        -- GLOBAL ----------
                        DONE            <= '0';
                        
                        -- CONTROL ---------
                        SEL_LOW         <= "11";
                        WRITE_LAST      <= '1';
    
                        -- KEY -------------
                        K_RDEN          <= '0';                  
                        K_WREN          <= '0';   
                        
                        -- ERROR -----------
                        RESULT_RDEN     <= '1';
                        RESULT_WREN     <= '1'; 
                        
                        -- MESSAGE ---------
                        M_RDEN          <= '0';
                                            
                        -- COUNTER ---------
                        CNT_ROW_EN      <= '0';
                        CNT_ROW_RST     <= '1';
                        
                        CNT_COL_EN      <= '0';
                        CNT_COL_RST     <= '0';
     
                        CNT_SHIFT_EN    <= '0';
                        CNT_SHIFT_RST   <= '0';               
                        
                        -- TRANSITION ------
                        STATE           <= S_DONE;                   
                    ---------------------------------------------- 
                                                            
                    ----------------------------------------------
                    WHEN S_DONE         =>   
                        -- GLOBAL ----------
                        DONE            <= '1';
                        
                        -- PRIVATE KEY -----
                        K_RDEN          <= '0';
                        K_WREN          <= '0';
    
                        -- ERROR -----------
                        RESULT_RDEN     <= '0';
                        RESULT_WREN     <= '0';
    
                        -- MESSAGE ---------
                        M_RDEN          <= '0';                
                        
                        CNT_ROW_EN      <= '0';
                        CNT_ROW_RST     <= '1';
    
                        CNT_COL_EN      <= '0';
                        CNT_COL_RST     <= '1';
                                            
                        CNT_SHIFT_EN    <= '0';
                        CNT_SHIFT_RST   <= '1';                            
                                 
                        -- TRANSITION ------
                        STATE           <= S_RESET;
                    ----------------------------------------------
                                    
                END CASE;
            END IF;
        END IF;
    END PROCESS;
    ------------------------------------------------------------------------------

END Behavioral;

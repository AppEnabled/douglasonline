<?php
/** @author Tamelo Douglas <tamelodouglas@gmail.com>
 * 
*/
class MysqlDatabase
{
    
    private $server;
    private $user;
    private $passwd;
    private $dbname;
    private static $conn = null;
    
    function __construct(){
        
            $this->server 	= DB_SERVER;	// The database host server
            $this->user 	= DB_USER;		// The database username
            $this->passwd 	= DB_PASS;	// The database password
            $this->dbname 	= DB_NAME;      // The database table

        $this->open_connection() ;
    }

    /**
     * connect to database
     */
    function open_connection(){
        if(self::$conn ==NULL){
                self::$conn  = mysqli_connect($this->server, $this->user ,$this->passwd,$this->dbname);
                if(!self::$conn){
                    die("Connection error.......".mysqli_connect_error());
                }
        }
        return self::$conn ;
    }
  
    /**
     * Close database connection
     * 
     * @return void
     */
    function close_connection()
    {
        if(isset(self::$conn)){
            self::$conn = null;
        }
    }
    
    /**
     * Get database results
     *
     * @param [type] $sql
     * @return void
     */
   public function db_query($sql){
 
        $this->result = mysqli_query(self::$conn,$sql);
        $this->confirm_query($this->result);  
        return $this->result;
   }
    
    public function confirm_query($result ){
       
        if(!$result){
         
            die("Database query failed ".  $result);
        }
        
    }
    
    
   function db_fetch_array($result){
        
       $myrow = mysqli_fetch_array($result);
      
       return $myrow;
    }
    
     function num_rows($result){
        
       $myrow = mysqli_num_rows($result);
      
       return $myrow;
    }
}
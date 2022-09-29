// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IERC20 { // Bizim amacımız ödenek almak veye duruma göre göndermek. Bunun için Transfer fonksiyonları bizim için yeterli.
    function transfer(address, uint) external returns(bool);
    function transferFrom( 
        address,
        address,
        uint
    ) external returns(bool);      
}

contract CrowdFund  {
    // Eventler: Bu aşamayı adım adım yapmanız daha faydalı yani: Önce Cancel fonksiyonunu yazıp sonrasında eventini yazın gibi.
    event Cancel(uint id);
    event Pledge(uint indexed id, address indexed caller, uint amount);
    event Unpledge(uint indexed id, address indexed caller, uint amount);
    event Claim(uint id);
    event Refund(uint id, address indexed caller, uint amount);

    // Campaign struct'ının oluşturulması: Bir kampanyanın hangi özellikleri vardır? Kampanyaların sahip olması gereken degiskenler:
    struct Campaign{
        address creator;
        uint goal;
        uint pledged;
        uint32 startAt;
        uint32 endAt;
        bool claimed;
    }    

    IERC20 public immutable token; /* ERC20 token değişkeni oluşturuyoruz. Burada bu değişken immutable 
    çünkü biz sadece tek bir token ödenegi kabul etmek istiyoruz güvenlik için. 
    */
    uint public count; // oluşturulan kampanyaların sayısını tutan degisken
    mapping (uint =>Campaign) public campaigns; // kampanyalara id vermemizi saglayan mapping
    mapping(uint => mapping(address => uint)) public pledgedAmount; /*  campaign id => pledger => amount pledged
    Kullanıcının hangi kampanyaya ne kadar ödenek verdigini takip etmemizi saglayan mapping. */

    constructor(address _token){ 
        token = IERC20(_token); // Token adressinin verilmesi
    }

    function launch( // Kampanya başlatan fonksiyon. Hedefimizi, başlama ve bitiş zamanlarını veriyoruz.
        uint _goal,
        uint32 _startAt,
        uint32 _endAt
    ) external {
        require(_startAt >= block.timestamp, "start at < now");
        require(_endAt >= _startAt , "end at < start at");
        require(_endAt <= block.timestamp + 90 days, "end at > max duration");
        count += 1; // Yeni kampanya oluştuğu için count artar.
        campaigns[count] = Campaign({ // Yeni kampanyanın oluşturulması.
            creator: msg.sender,
            goal: _goal,
            pledged: 0, // yeni başladığı için henüz ödenek almadık.
            startAt: _startAt,
            endAt: _endAt,
            claimed: false 
        });


    }

    function cancel(uint _id) external{ // Kampanyayı silen fonksyion.
        Campaign memory campaign = campaigns[_id]; 
        require(campaign.creator == msg.sender, "not creator"); // sadece creatorlar cagirabilir.
        require(block.timestamp < campaign.startAt, "started"); // başlamamış olması gerek.
        delete campaigns[_id];
        emit Cancel(_id);

    }

    function pledge(uint _id, uint _amounth) external{
        Campaign storage campaign = campaigns[_id]; // burada Storage kullanmamızın nedeni Campaign struct'ında bir güncellemeye gitmemiz.
        require(block.timestamp >= campaign.startAt, "not started"); // başlamış olması gerek.
        require(block.timestamp <= campaign.endAt, "ended"); // bitmemiş olması gerek.
        campaign.pledged += _amounth; // Campaign structını güncelliyor.
        pledgedAmount[_id][msg.sender] += _amounth; // kullanıcının bu kampanyadaki durumunu günceller.
        token.transferFrom(msg.sender, address(this), _amounth); // ödenegi kontrata aktarır.
        emit Pledge(_id, msg.sender, _amounth);
    }

    function unpladge(uint _id, uint _amounth) external{ // pledge işlemi ile neredeyse aynı. sadece tersi yönünde işlem yapılıyor.
        Campaign storage campaign = campaigns[_id]; 
        require(block.timestamp <= campaign.endAt, "ended");
        campaign.pledged -= _amounth;
        pledgedAmount[_id][msg.sender] -= _amounth;
        token.transfer(msg.sender, _amounth);
        emit Unpledge(_id, msg.sender, _amounth);
    }

    function claim(uint _id) external{
        Campaign storage campaign = campaigns[_id];
        require(campaign.creator == msg.sender, "not creator"); // sadece creatorlar cagirabilir.
        require(block.timestamp > campaign.endAt, "not ended"); // bitmis olmasi gerekir.
        require(campaign.pledged >= campaign.goal, " pledged < goal "); // hedefe ulasmis olması gerekir.
        require(!campaign.claimed, "claimed"); // henuz claimlenmemis olmasi gerekir.
        campaign.claimed = true;
        token.transfer(campaign.creator, campaign.pledged);
        emit Claim(_id);
    }
    
    // Eğer kampanya hedefine ulasamaz ise kullanıcılar paralarını geri cekebilirler. 
    function refund(uint _id) external{
        Campaign memory campaign = campaigns[_id];
        require(block.timestamp > campaign.endAt, "not ended"); // bitmis olmasi gerekir.
        require(campaign.pledged < campaign.goal, "pledged >= goal"); // amacına ulasmamis olmasi gerekir.
        uint bal = pledgedAmount[_id][msg.sender]; // iade edilecek miktarın hesaplanmasi.
        pledgedAmount[_id][msg.sender] = 0; //reentrancy attack engellemek icin isimizi saglama aliyoruz.
        token.transfer(msg.sender, bal); // iade gerceklesir.
        emit Refund(_id, msg.sender, bal);
    }

}
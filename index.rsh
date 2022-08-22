'reach 0.1';

const [isOutcome, NOT_PASSED, PASSED, INPROGRESS] = makeEnum(3)

const DEADLINE = 20;

const state = Bytes(20);


const checkStatus = (numMembers, upVotes, downVotes) => {
 const result = downVotes > numMembers * 50 / 100 ? NOT_PASSED : 
                upVotes > numMembers * 50 / 100 ? PASSED :
                INPROGRESS;
   return result;
};

assert(checkStatus(100, 0, 51) == NOT_PASSED);
assert(checkStatus(100, 0, 0) == INPROGRESS);
assert(checkStatus(100, 51, 0) == PASSED);


forall(UInt, numMembers => 
 forall(UInt, upVotes => 
  forall(UInt, downVotes => 
   assert(isOutcome(checkStatus(numMembers, upVotes, downVotes))))));

const common = {
 seeOutcome: Fun([UInt, UInt], Null),
 informTimeout: Fun([], Null),
}

export const main = Reach.App(() => {
   setOptions({untrustworthyMaps: true});
 const Deployer = Participant('Deployer', {
  ...common,
  getProposal: Object({
   title: Bytes(48),
   link: Bytes(128),
   description: Bytes(200),
   owner: Address,
   contract: Contract,
   ID: UInt,
  }),
  numMembers: UInt,
  projectPassed: Fun([], Null),
  projectNotPassed: Fun([], Null),
  // interact interface here
 });
 
 const Voters = API('Voters', {
  ...common,
  upvote: Fun([], Null),
  downvote: Fun([], Null),
  contribute: Fun([UInt], Null),
  // interact interface 
 });

 const Proposals = Events({
   log: [state, UInt]
 });
 init();

    Deployer.only(() => {
        const {title, link, description, owner, contract, ID} = declassify(interact.getProposal);
        const numMembers = declassify(interact.numMembers);
    });
    Deployer.publish(title, link, description, owner, contract, numMembers, ID);
 Proposals.log(state.pad('created'), ID)
 commit();

 Deployer.publish();


 const end = lastConsensusTime() + DEADLINE;
    commit();

    Deployer.publish();
    const contributors = new Map(UInt, Object({
        address: Address,
        amt: UInt,
    }));


 const [
   upvote,
   downvote,
   count,
   amtTotal,
   lastAddress,
   keepGoing,
 ] = parallelReduce([ 0, 0, 0, 0, Deployer, true])
   .invariant(balance() == amtTotal)
   .while(lastConsensusTime() <= end && keepGoing)
   .api(Voters.upvote, (notify) => {
      notify(null);
      return [upvote + 1, downvote, count, amtTotal, lastAddress, checkStatus(upvote + 1, downvote, numMembers) == INPROGRESS ? true : false]
   })
   .api(Voters.downvote, (notify) => {
      notify(null);
      return [upvote, downvote + 1, count, amtTotal, lastAddress, checkStatus(upvote, downvote + 1, numMembers) == INPROGRESS ? true : false]
   })
   .api_(Voters.contribute, (amt) => {
      const payment = amt;
      return [payment, (notify) => {
         notify(null);
         contributors[count] = {address: this, amt: amt}
         return [upvote, downvote, count + 1, amtTotal + amt, this, keepGoing]
      }]
   })
   .timeout(absoluteTime(end), () => {
      Deployer.publish();
      Proposals.log(state.pad('timeout'), ID);
      return [upvote, downvote, count, amtTotal, lastAddress, keepGoing];   
   }); 

   if(checkStatus(numMembers,upvote,downvote) == PASSED){
      Proposals.log(state.pad('passed'), ID);
      transfer(balance()).to(owner);
   } 
   else if (checkStatus(numMembers,upvote,downvote) == INPROGRESS) {
      if (upvote > downvote && upvote + downvote > numMembers * 50 / 100) {
         Proposals.log(state.pad('passed'), ID);
         transfer(balance()).to(owner);
      }else {
         Proposals.log(state.pad('failed'), ID);
         const fromMap = (m) => fromMaybe(m, (() => ({ address: lastAddress, amt: 0 })), ((x) => x));
         commit();
         Deployer.publish();
         var [newCount, currentBalance] = [count, balance()];
         invariant(balance() == currentBalance);
         while(newCount > 0) {
            commit();
            Deployer.publish();

            if(balance() >= fromMap(contributors[newCount]).amt) { 
               transfer(fromMap(contributors[newCount]).amt).to(
                  fromMap(contributors[newCount]).address
               );
            }
            [newCount, currentBalance] = [newCount - 1, balance()];
            continue;
         }

      }

   }else {
      Proposals.log(state.pad('failed'), ID);
      const fromMap = (m) => fromMaybe(m, (() => ({ address: lastAddress, amt: 0 })), ((x) => x));
      commit();
      Deployer.publish();
      var [newCount, currentBalance] = [count, balance()];
      invariant(balance() == currentBalance);
      while(newCount > 0) {
         commit();
         Deployer.publish();

        if (balance() >= fromMap(contributors[newCount]).amt) { 
                transfer(fromMap(contributors[newCount]).amt).to(
                    fromMap(contributors[newCount]).address
                );
            }
            [newCount, currentBalance] = [newCount - 1, balance()];
            continue;
      }
   }
   transfer(balance()).to(Deployer);
   commit();
});



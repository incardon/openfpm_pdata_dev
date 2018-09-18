
#define BOOST_TEST_DYN_LINK
#include <boost/test/unit_test.hpp>
#include "VCluster/VCluster.hpp"
#include <Vector/vector_dist.hpp>
#include "Vector/tests/vector_dist_util_unit_tests.hpp"

#define SUB_UNIT_FACTOR 1024

template<unsigned int dim , typename vector_dist_type>
__global__ void move_parts_gpu_test(vector_dist_type vd)
{
	auto p = GET_PARTICLE(vd);

#pragma unroll
	for (int i = 0 ; i < dim ; i++)
	{
		vd.getPos(p)[i] += 0.05;
	}
}

BOOST_AUTO_TEST_SUITE( vector_dist_gpu_test )

void print_test(std::string test, size_t sz)
{
	if (create_vcluster().getProcessUnitID() == 0)
		std::cout << test << " " << sz << "\n";
}


__global__  void initialize_props(vector_dist_ker<3, float, aggregate<float, float [3], float[3]>> vd)
{
	auto p = GET_PARTICLE(vd);

	vd.template getProp<0>(p) = vd.getPos(p)[0] + vd.getPos(p)[1] + vd.getPos(p)[2];

	vd.template getProp<1>(p)[0] = vd.getPos(p)[0] + vd.getPos(p)[1];
	vd.template getProp<1>(p)[1] = vd.getPos(p)[0] + vd.getPos(p)[2];
	vd.template getProp<1>(p)[2] = vd.getPos(p)[1] + vd.getPos(p)[2];
}

template<typename CellList_type>
__global__  void calculate_force(vector_dist_ker<3, float, aggregate<float, float[3], float [3]>> vd,
		                         vector_dist_ker<3, float, aggregate<float, float[3], float [3]>> vd_sort,
		                         CellList_type cl)
{
	auto p = GET_PARTICLE(vd);

	Point<3,float> xp = vd.getPos(p);

    auto it = cl.getNNIterator(cl.getCell(xp));

    auto cell = cl.getCell(xp);

    Point<3,float> force1({0.0,0.0,0.0});
    Point<3,float> force2({0.0,0.0,0.0});

    while (it.isNext())
    {
    	auto q1 = it.get();
    	auto q2 = it.get_orig();

    	if (q2 == p) {++it; continue;}

    	Point<3,float> xq_1 = vd_sort.getPos(q1);
    	Point<3,float> xq_2 = vd.getPos(q2);

    	Point<3,float> r1 = xq_1 - xp;
    	Point<3,float> r2 = xq_2 - xp;

    	// Normalize

    	r1 /= r1.norm();
    	r2 /= r2.norm();

    	force1 += vd_sort.template getProp<0>(q1)*r1;
    	force2 += vd.template getProp<0>(q2)*r2;

    	++it;
    }

    vd.template getProp<1>(p)[0] = force1.get(0);
    vd.template getProp<1>(p)[1] = force1.get(1);
    vd.template getProp<1>(p)[2] = force1.get(2);

    vd.template getProp<2>(p)[0] = force2.get(0);
    vd.template getProp<2>(p)[1] = force2.get(1);
    vd.template getProp<2>(p)[2] = force2.get(2);
}

template<typename CellList_type>
__global__  void calculate_force_full_sort(vector_dist_ker<3, float, aggregate<float, float[3], float [3]>> vd,
		                         	 	   CellList_type cl)
{
	auto p = GET_PARTICLE(vd);

	Point<3,float> xp = vd.getPos(p);

    auto it = cl.getNNIterator(cl.getCell(xp));

    auto cell = cl.getCell(xp);

    Point<3,float> force1({0.0,0.0,0.0});

    while (it.isNext())
    {
    	auto q1 = it.get();

    	if (q1 == p) {++it; continue;}

    	Point<3,float> xq_1 = vd.getPos(q1);

    	Point<3,float> r1 = xq_1 - xp;

    	// Normalize

    	r1 /= r1.norm();

    	force1 += vd.template getProp<0>(q1)*r1;

    	++it;
    }

    vd.template getProp<1>(p)[0] = force1.get(0);
    vd.template getProp<1>(p)[1] = force1.get(1);
    vd.template getProp<1>(p)[2] = force1.get(2);
}

template<typename CellList_type, typename vector_type>
bool check_force(CellList_type & NN_cpu, vector_type & vd)
{
	auto it6 = vd.getDomainIterator();

	bool match = true;

	while (it6.isNext())
	{
		auto p = it6.get();

		Point<3,float> xp = vd.getPos(p);

		// Calculate on CPU

		Point<3,float> force({0.0,0.0,0.0});

		auto NNc = NN_cpu.getNNIterator(NN_cpu.getCell(xp));

		while (NNc.isNext())
		{
			auto q = NNc.get();

	    	if (q == p.getKey()) {++NNc; continue;}

	    	Point<3,float> xq_2 = vd.getPos(q);
	    	Point<3,float> r2 = xq_2 - xp;

	    	// Normalize

	    	r2 /= r2.norm();
	    	force += vd.template getProp<0>(q)*r2;

			++NNc;
		}

		match &= fabs(vd.template getProp<1>(p)[0] - vd.template getProp<2>(p)[0]) < 0.0001;
		match &= fabs(vd.template getProp<1>(p)[1] - vd.template getProp<2>(p)[1]) < 0.0001;
		match &= fabs(vd.template getProp<1>(p)[2] - vd.template getProp<2>(p)[2]) < 0.0001;

		match &= fabs(vd.template getProp<1>(p)[0] - force.get(0)) < 0.0001;
		match &= fabs(vd.template getProp<1>(p)[1] - force.get(1)) < 0.0001;
		match &= fabs(vd.template getProp<1>(p)[2] - force.get(2)) < 0.0001;

		++it6;
	}

	return match;
}

BOOST_AUTO_TEST_CASE( vector_dist_gpu_ghost_get )
{
	auto & v_cl = create_vcluster();

	if (v_cl.size() > 16)
	{return;}

	Box<3,float> domain({0.0,0.0,0.0},{1.0,1.0,1.0});

	// set the ghost based on the radius cut off (make just a little bit smaller than the spacing)
	Ghost<3,float> g(0.1);

	// Boundary conditions
	size_t bc[3]={PERIODIC,PERIODIC,PERIODIC};

	vector_dist_gpu<3,float,aggregate<float,float[3],float[3]>> vd(1000,domain,bc,g);

	auto it = vd.getDomainIterator();

	while (it.isNext())
	{
		auto p = it.get();

		vd.getPos(p)[0] = (float)rand() / RAND_MAX;
		vd.getPos(p)[1] = (float)rand() / RAND_MAX;
		vd.getPos(p)[2] = (float)rand() / RAND_MAX;

		vd.template getProp<0>(p) = vd.getPos(p)[0] + vd.getPos(p)[1] + vd.getPos(p)[2];

		vd.template getProp<1>(p)[0] = vd.getPos(p)[0] + vd.getPos(p)[1];
		vd.template getProp<1>(p)[1] = vd.getPos(p)[0] + vd.getPos(p)[2];
		vd.template getProp<1>(p)[2] = vd.getPos(p)[1] + vd.getPos(p)[2];

		vd.template getProp<2>(p)[0] = vd.getPos(p)[0] + 3.0*vd.getPos(p)[1];
		vd.template getProp<2>(p)[1] = vd.getPos(p)[0] + 3.0*vd.getPos(p)[2];
		vd.template getProp<2>(p)[2] = vd.getPos(p)[1] + 3.0*vd.getPos(p)[2];


		++it;
	}

	// Ok we redistribute the particles (CPU based)
	vd.map();

	vd.template ghost_get<0,1,2>();

	// Now we check the the ghost contain the correct information

	bool check = true;

	auto itg = vd.getDomainAndGhostIterator();

	while (itg.isNext())
	{
		auto p = itg.get();

		check &= (vd.template getProp<0>(p) == vd.getPos(p)[0] + vd.getPos(p)[1] + vd.getPos(p)[2]);

		check &= (vd.template getProp<1>(p)[0] == vd.getPos(p)[0] + vd.getPos(p)[1]);
		check &= (vd.template getProp<1>(p)[1] == vd.getPos(p)[0] + vd.getPos(p)[2]);
		check &= (vd.template getProp<1>(p)[2] == vd.getPos(p)[1] + vd.getPos(p)[2]);

		check &= (vd.template getProp<2>(p)[0] == vd.getPos(p)[0] + 3.0*vd.getPos(p)[1]);
		check &= (vd.template getProp<2>(p)[1] == vd.getPos(p)[0] + 3.0*vd.getPos(p)[2]);
		check &= (vd.template getProp<2>(p)[2] == vd.getPos(p)[1] + 3.0*vd.getPos(p)[2]);

		++itg;
	}

	size_t tot_s = vd.size_local_with_ghost();

	v_cl.sum(tot_s);
	v_cl.execute();

	// We check that we check something
	BOOST_REQUIRE(tot_s > 1000);
}

template<typename vector_type, typename CellList_type, typename CellList_type_cpu>
void check_cell_list_cpu_and_gpu(vector_type & vd, CellList_type & NN, CellList_type_cpu & NN_cpu)
{
	auto it5 = vd.getDomainIteratorGPU();

	calculate_force<decltype(NN.toKernel())><<<it5.wthr,it5.thr>>>(vd.toKernel(),vd.toKernel_sorted(),NN.toKernel());

	vd.template deviceToHostProp<1,2>();

	bool test = check_force(NN_cpu,vd);
	BOOST_REQUIRE_EQUAL(test,true);

	// We do exactly the same test as before, but now we completely use the sorted version

	calculate_force_full_sort<decltype(NN.toKernel())><<<it5.wthr,it5.thr>>>(vd.toKernel_sorted(),NN.toKernel());

	vd.template deviceToHostProp<1>();

	test = check_force(NN_cpu,vd);
	BOOST_REQUIRE_EQUAL(test,true);
}

BOOST_AUTO_TEST_CASE( vector_dist_gpu_test)
{
	auto & v_cl = create_vcluster();

	if (v_cl.size() > 16)
	{return;}

	Box<3,float> domain({0.0,0.0,0.0},{1.0,1.0,1.0});

	// set the ghost based on the radius cut off (make just a little bit smaller than the spacing)
	Ghost<3,float> g(0.1);

	// Boundary conditions
	size_t bc[3]={NON_PERIODIC,NON_PERIODIC,NON_PERIODIC};

	vector_dist_gpu<3,float,aggregate<float,float[3],float[3]>> vd(1000,domain,bc,g);

	auto it = vd.getDomainIterator();

	while (it.isNext())
	{
		auto p = it.get();

		vd.getPos(p)[0] = (float)rand() / RAND_MAX;
		vd.getPos(p)[1] = (float)rand() / RAND_MAX;
		vd.getPos(p)[2] = (float)rand() / RAND_MAX;

		++it;
	}

	// Ok we redistribute the particles (CPU based)
	vd.map();

	size_t size_l = vd.size_local();

	v_cl.sum(size_l);
	v_cl.execute();

	BOOST_REQUIRE_EQUAL(size_l,1000);


	auto & ct = vd.getDecomposition();

	bool noOut = true;
	size_t cnt = 0;

	auto it2 = vd.getDomainIterator();

	while (it2.isNext())
	{
		auto p = it2.get();

		noOut &= ct.isLocal(vd.getPos(p));

		cnt++;
		++it2;
	}

	BOOST_REQUIRE_EQUAL(noOut,true);
	BOOST_REQUIRE_EQUAL(cnt,vd.size_local());

	vd.write("test_out_gpu");

	// now we offload all the properties

	auto it3 = vd.getDomainIteratorGPU();

	// offload to device
	vd.hostToDevicePos();

	initialize_props<<<it3.wthr,it3.thr>>>(vd.toKernel());

	// now we check what we initialized

	vd.deviceToHostProp<0,1>();

	auto it4 = vd.getDomainIterator();

	while (it4.isNext())
	{
		auto p = it4.get();

		BOOST_REQUIRE_CLOSE(vd.template getProp<0>(p),vd.getPos(p)[0] + vd.getPos(p)[1] + vd.getPos(p)[2],0.01);

		BOOST_REQUIRE_CLOSE(vd.template getProp<1>(p)[0],vd.getPos(p)[0] + vd.getPos(p)[1],0.01);
		BOOST_REQUIRE_CLOSE(vd.template getProp<1>(p)[1],vd.getPos(p)[0] + vd.getPos(p)[2],0.01);
		BOOST_REQUIRE_CLOSE(vd.template getProp<1>(p)[2],vd.getPos(p)[1] + vd.getPos(p)[2],0.01);

		//std::cout << "PROP 0 " << vd.template getProp<0>(p) << "   " << vd.getPos(p)[0] + vd.getPos(p)[1] + vd.getPos(p)[2] << std::endl;

		++it4;
	}

	// here we do a ghost_get
	vd.ghost_get<0>();

	// we re-offload what we received
	vd.hostToDevicePos();
	vd.template hostToDeviceProp<0>();

	auto NN = vd.getCellListGPU(0.1);
	auto NN_cpu = vd.getCellList(0.1);

	auto NN_up = vd.getCellListGPU(0.1);
	NN_up.clear();
	vd.updateCellList(NN_up);

	check_cell_list_cpu_and_gpu(vd,NN,NN_cpu);
	check_cell_list_cpu_and_gpu(vd,NN_up,NN_cpu);

	// We check if we opotain the same result from updateCellList



	// check

	// Now we do a ghost_get from CPU

	// Than we offload on GPU

	// We construct a Cell-list

	// We calculate force on CPU and GPU to check if they match



}

template<typename St>
void vdist_calc_gpu_test()
{
	auto & v_cl = create_vcluster();

	if (v_cl.size() > 16)
	{return;}

	Box<3,St> domain({0.0,0.0,0.0},{1.0,1.0,1.0});

	// set the ghost based on the radius cut off (make just a little bit smaller than the spacing)
	Ghost<3,St> g(0.1);

	// Boundary conditions
	size_t bc[3]={PERIODIC,PERIODIC,PERIODIC};

	vector_dist_gpu<3,St,aggregate<float,float[3],float[3]>> vd(1000,domain,bc,g);

	auto it = vd.getDomainIterator();

	while (it.isNext())
	{
		auto p = it.get();

		vd.getPos(p)[0] = (St)rand() / RAND_MAX;
		vd.getPos(p)[1] = (St)rand() / RAND_MAX;
		vd.getPos(p)[2] = (St)rand() / RAND_MAX;

		vd.template getProp<0>(p) = vd.getPos(p)[0] + vd.getPos(p)[1] + vd.getPos(p)[2];

		vd.template getProp<1>(p)[0] = vd.getPos(p)[0];
		vd.template getProp<1>(p)[1] = vd.getPos(p)[1];
		vd.template getProp<1>(p)[2] = vd.getPos(p)[2];

		vd.template getProp<2>(p)[0] = vd.getPos(p)[0] + vd.getPos(p)[1];
		vd.template getProp<2>(p)[1] = vd.getPos(p)[0] + vd.getPos(p)[2];
		vd.template getProp<2>(p)[2] = vd.getPos(p)[1] + vd.getPos(p)[2];

		++it;
	}

	// move on device
	vd.hostToDevicePos();
	vd.template hostToDeviceProp<0,1,2>();

	// Ok we redistribute the particles (GPU based)
	vd.map(RUN_ON_DEVICE);

	vd.deviceToHostPos();
	vd.template deviceToHostProp<0,1,2>();

	vd.write("write_start");

	// Reset the host part

	auto it3 = vd.getDomainIterator();

	while (it3.isNext())
	{
		auto p = it3.get();

		vd.getPos(p)[0] = 1.0;
		vd.getPos(p)[1] = 1.0;
		vd.getPos(p)[2] = 1.0;

		vd.template getProp<0>(p) = 0.0;

		vd.template getProp<0>(p) = 0.0;
		vd.template getProp<0>(p) = 0.0;
		vd.template getProp<0>(p) = 0.0;

		vd.template getProp<0>(p) = 0.0;
		vd.template getProp<0>(p) = 0.0;
		vd.template getProp<0>(p) = 0.0;

		++it3;
	}

	// we move from Device to CPU

	vd.deviceToHostPos();
	vd.template deviceToHostProp<0,1,2>();

	// Check

	auto it2 = vd.getDomainIterator();

	bool match = true;
	while (it2.isNext())
	{
		auto p = it2.get();

		match &= vd.template getProp<0>(p) == vd.getPos(p)[0] + vd.getPos(p)[1] + vd.getPos(p)[2];

		match &= vd.template getProp<1>(p)[0] == vd.getPos(p)[0];
		match &= vd.template getProp<1>(p)[1] == vd.getPos(p)[1];
		match &= vd.template getProp<1>(p)[2] == vd.getPos(p)[2];

		match &= vd.template getProp<2>(p)[0] == vd.getPos(p)[0] + vd.getPos(p)[1];
		match &= vd.template getProp<2>(p)[1] == vd.getPos(p)[0] + vd.getPos(p)[2];
		match &= vd.template getProp<2>(p)[2] == vd.getPos(p)[1] + vd.getPos(p)[2];

		++it2;
	}

	BOOST_REQUIRE_EQUAL(match,true);

	// count local particles

	size_t l_cnt = 0;
	size_t nl_cnt = 0;
	size_t n_out = 0;

	// Domain + ghost box
	Box<3,St> dom_ext = domain;
	dom_ext.enlarge(g);

	auto it5 = vd.getDomainIterator();
	count_local_n_local<3>(vd,it5,bc,domain,dom_ext,l_cnt,nl_cnt,n_out);

	BOOST_REQUIRE_EQUAL(n_out,0);
	BOOST_REQUIRE_EQUAL(l_cnt,vd.size_local());

	// we do 10 gpu steps (using a cpu vector to check that map and ghost get work as expented)

	for (size_t i = 0 ; i < 10 ; i++)
	{
		vd.map(RUN_ON_DEVICE);

		vd.deviceToHostPos();
		vd.template deviceToHostProp<0,1,2>();

		vd.write_frame("write_ggg",i);


		// To test we copy on a cpu distributed vector and we do a map

		vector_dist<3,St,aggregate<float,float[3],float[3]>> vd_cpu(vd.getDecomposition().template duplicate_convert<HeapMemory,memory_traits_lin>(),0);

		auto itc = vd.getDomainIterator();

		while (itc.isNext())
		{
			auto p = itc.get();

			vd_cpu.add();

			vd_cpu.getLastPos()[0] = vd.getPos(p)[0];
			vd_cpu.getLastPos()[1] = vd.getPos(p)[1];
			vd_cpu.getLastPos()[2] = vd.getPos(p)[2];

			vd_cpu.template getLastProp<0>() = vd.template getProp<0>(p);

			vd_cpu.template getLastProp<1>()[0] = vd.template getProp<1>(p)[0];
			vd_cpu.template getLastProp<1>()[1] = vd.template getProp<1>(p)[1];
			vd_cpu.template getLastProp<1>()[2] = vd.template getProp<1>(p)[2];

			vd_cpu.template getLastProp<2>()[0] = vd.template getProp<2>(p)[0];
			vd_cpu.template getLastProp<2>()[1] = vd.template getProp<2>(p)[1];
			vd_cpu.template getLastProp<2>()[2] = vd.template getProp<2>(p)[2];

			++itc;
		}

		vd_cpu.template ghost_get<0,1,2>();
		vd.template ghost_get<0,1,2>(RUN_ON_DEVICE);

		vd.deviceToHostPos();
		vd.template deviceToHostProp<0,1,2>();

		match = true;

		// Particle on the gpu ghost and cpu ghost are not ordered in the same way so we have to reorder

		struct part
		{
			Point<3,St> xp;

			float prp0;
			float prp1[3];
			float prp2[3];

			bool operator<(const part & tmp) const
			{
				if (xp.get(0) < tmp.xp.get(0))
				{return true;}
				else if (xp.get(0) > tmp.xp.get(0))
				{return false;}

				if (xp.get(1) < tmp.xp.get(1))
				{return true;}
				else if (xp.get(1) > tmp.xp.get(1))
				{return false;}

				if (xp.get(2) < tmp.xp.get(2))
				{return true;}
				else if (xp.get(2) > tmp.xp.get(2))
				{return false;}

				return false;
			}
		};

		openfpm::vector<part> cpu_sort;
		openfpm::vector<part> gpu_sort;

		cpu_sort.resize(vd_cpu.size_local_with_ghost() - vd_cpu.size_local());
		gpu_sort.resize(vd.size_local_with_ghost() - vd.size_local());

		size_t cnt = 0;

		auto itc2 = vd.getGhostIterator();
		while (itc2.isNext())
		{
			auto p = itc2.get();

			cpu_sort.get(cnt).xp.get(0) = vd_cpu.getPos(p)[0];
			gpu_sort.get(cnt).xp.get(0) = vd.getPos(p)[0];
			cpu_sort.get(cnt).xp.get(1) = vd_cpu.getPos(p)[1];
			gpu_sort.get(cnt).xp.get(1) = vd.getPos(p)[1];
			cpu_sort.get(cnt).xp.get(2) = vd_cpu.getPos(p)[2];
			gpu_sort.get(cnt).xp.get(2) = vd.getPos(p)[2];

			cpu_sort.get(cnt).prp0 = vd_cpu.template getProp<0>(p);
			gpu_sort.get(cnt).prp0 = vd.template getProp<0>(p);

			cpu_sort.get(cnt).prp1[0] = vd_cpu.template getProp<1>(p)[0];
			gpu_sort.get(cnt).prp1[0] = vd.template getProp<1>(p)[0];
			cpu_sort.get(cnt).prp1[1] = vd_cpu.template getProp<1>(p)[1];
			gpu_sort.get(cnt).prp1[1] = vd.template getProp<1>(p)[1];
			cpu_sort.get(cnt).prp1[2] = vd_cpu.template getProp<1>(p)[2];
			gpu_sort.get(cnt).prp1[2] = vd.template getProp<1>(p)[2];

			cpu_sort.get(cnt).prp2[0] = vd_cpu.template getProp<2>(p)[0];
			gpu_sort.get(cnt).prp2[0] = vd.template getProp<2>(p)[0];
			cpu_sort.get(cnt).prp2[1] = vd_cpu.template getProp<2>(p)[1];
			gpu_sort.get(cnt).prp2[1] = vd.template getProp<2>(p)[1];
			cpu_sort.get(cnt).prp2[2] = vd_cpu.template getProp<2>(p)[2];
			gpu_sort.get(cnt).prp2[2] = vd.template getProp<2>(p)[2];

			++cnt;
			++itc2;
		}

		cpu_sort.sort();
		gpu_sort.sort();

		for (size_t i = 0 ; i < cpu_sort.size() ; i++)
		{
			match &= cpu_sort.get(i).xp.get(0) == gpu_sort.get(i).xp.get(0);
			match &= cpu_sort.get(i).xp.get(1) == gpu_sort.get(i).xp.get(1);
			match &= cpu_sort.get(i).xp.get(2) == gpu_sort.get(i).xp.get(2);

			match &= cpu_sort.get(i).prp0 == gpu_sort.get(i).prp0;
			match &= cpu_sort.get(i).prp1[0] == gpu_sort.get(i).prp1[0];
			match &= cpu_sort.get(i).prp1[1] == gpu_sort.get(i).prp1[1];
			match &= cpu_sort.get(i).prp1[2] == gpu_sort.get(i).prp1[2];

			match &= cpu_sort.get(i).prp2[0] == gpu_sort.get(i).prp2[0];
			match &= cpu_sort.get(i).prp2[1] == gpu_sort.get(i).prp2[1];
			match &= cpu_sort.get(i).prp2[2] == gpu_sort.get(i).prp2[2];
		}

		BOOST_REQUIRE_EQUAL(match,true);

		// move particles on gpu

		auto ite = vd.getDomainIteratorGPU();
		move_parts_gpu_test<3,decltype(vd.toKernel())><<<ite.wthr,ite.thr>>>(vd.toKernel());
	}
}

BOOST_AUTO_TEST_CASE( vector_dist_map_on_gpu_test)
{
	vdist_calc_gpu_test<float>();
	vdist_calc_gpu_test<double>();

/*	auto & v_cl = create_vcluster();

	if (v_cl.size() > 16)
	{return;}

	Box<3,float> domain({0.0,0.0,0.0},{1.0,1.0,1.0});

	// set the ghost based on the radius cut off (make just a little bit smaller than the spacing)
	Ghost<3,float> g(0.1);

	// Boundary conditions
	size_t bc[3]={PERIODIC,PERIODIC,PERIODIC};

	vector_dist_gpu<3,float,aggregate<float,float[3],float[3]>> vd(1000,domain,bc,g);

	auto it = vd.getDomainIterator();

	while (it.isNext())
	{
		auto p = it.get();

		vd.getPos(p)[0] = (float)rand() / RAND_MAX;
		vd.getPos(p)[1] = (float)rand() / RAND_MAX;
		vd.getPos(p)[2] = (float)rand() / RAND_MAX;

		vd.template getProp<0>(p) = vd.getPos(p)[0] + vd.getPos(p)[1] + vd.getPos(p)[2];

		vd.template getProp<1>(p)[0] = vd.getPos(p)[0];
		vd.template getProp<1>(p)[1] = vd.getPos(p)[1];
		vd.template getProp<1>(p)[2] = vd.getPos(p)[2];

		vd.template getProp<2>(p)[0] = vd.getPos(p)[0] + vd.getPos(p)[1];
		vd.template getProp<2>(p)[1] = vd.getPos(p)[0] + vd.getPos(p)[2];
		vd.template getProp<2>(p)[2] = vd.getPos(p)[1] + vd.getPos(p)[2];

		++it;
	}

	// move on device
	vd.hostToDevicePos();
	vd.hostToDeviceProp<0,1,2>();

	// Ok we redistribute the particles (GPU based)
	vd.map(RUN_ON_DEVICE);

	vd.deviceToHostPos();
	vd.deviceToHostProp<0,1,2>();

	vd.write("write_start");

	// Reset the host part

	auto it3 = vd.getDomainIterator();

	while (it3.isNext())
	{
		auto p = it3.get();

		vd.getPos(p)[0] = 1.0;
		vd.getPos(p)[1] = 1.0;
		vd.getPos(p)[2] = 1.0;

		vd.template getProp<0>(p) = 0.0;

		vd.template getProp<0>(p) = 0.0;
		vd.template getProp<0>(p) = 0.0;
		vd.template getProp<0>(p) = 0.0;

		vd.template getProp<0>(p) = 0.0;
		vd.template getProp<0>(p) = 0.0;
		vd.template getProp<0>(p) = 0.0;

		++it3;
	}

	// we move from Device to CPU

	vd.deviceToHostPos();
	vd.deviceToHostProp<0,1,2>();

	// Check

	auto it2 = vd.getDomainIterator();

	bool match = true;
	while (it2.isNext())
	{
		auto p = it2.get();

		match &= vd.template getProp<0>(p) == vd.getPos(p)[0] + vd.getPos(p)[1] + vd.getPos(p)[2];

		match &= vd.template getProp<1>(p)[0] == vd.getPos(p)[0];
		match &= vd.template getProp<1>(p)[1] == vd.getPos(p)[1];
		match &= vd.template getProp<1>(p)[2] == vd.getPos(p)[2];

		match &= vd.template getProp<2>(p)[0] == vd.getPos(p)[0] + vd.getPos(p)[1];
		match &= vd.template getProp<2>(p)[1] == vd.getPos(p)[0] + vd.getPos(p)[2];
		match &= vd.template getProp<2>(p)[2] == vd.getPos(p)[1] + vd.getPos(p)[2];

		++it2;
	}

	BOOST_REQUIRE_EQUAL(match,true);

	// count local particles

	size_t l_cnt = 0;
	size_t nl_cnt = 0;
	size_t n_out = 0;

	// Domain + ghost box
	Box<3,float> dom_ext = domain;
	dom_ext.enlarge(g);

	auto it5 = vd.getDomainIterator();
	count_local_n_local<3>(vd,it5,bc,domain,dom_ext,l_cnt,nl_cnt,n_out);

	BOOST_REQUIRE_EQUAL(n_out,0);
	BOOST_REQUIRE_EQUAL(l_cnt,vd.size_local());

	// we do 10 gpu steps (using a cpu vector to check that map and ghost get work as expented)

	for (size_t i = 0 ; i < 10 ; i++)
	{
		vd.map(RUN_ON_DEVICE);

		vd.deviceToHostPos();
		vd.deviceToHostProp<0,1,2>();

		vd.write_frame("write_ggg",i);


		// To test we copy on a cpu distributed vector and we do a map

		vector_dist<3,float,aggregate<float,float[3],float[3]>> vd_cpu(vd.getDecomposition().duplicate_convert<HeapMemory,memory_traits_lin>(),0);

		auto itc = vd.getDomainIterator();

		while (itc.isNext())
		{
			auto p = itc.get();

			vd_cpu.add();

			vd_cpu.getLastPos()[0] = vd.getPos(p)[0];
			vd_cpu.getLastPos()[1] = vd.getPos(p)[1];
			vd_cpu.getLastPos()[2] = vd.getPos(p)[2];

			vd_cpu.getLastProp<0>() = vd.getProp<0>(p);

			vd_cpu.getLastProp<1>()[0] = vd.getProp<1>(p)[0];
			vd_cpu.getLastProp<1>()[1] = vd.getProp<1>(p)[1];
			vd_cpu.getLastProp<1>()[2] = vd.getProp<1>(p)[2];

			vd_cpu.getLastProp<2>()[0] = vd.getProp<2>(p)[0];
			vd_cpu.getLastProp<2>()[1] = vd.getProp<2>(p)[1];
			vd_cpu.getLastProp<2>()[2] = vd.getProp<2>(p)[2];

			++itc;
		}

		vd_cpu.ghost_get<0,1,2>();
		vd.ghost_get<0,1,2>(RUN_ON_DEVICE);

		vd.deviceToHostPos();
		vd.deviceToHostProp<0,1,2>();

		match = true;

		// Particle on the gpu ghost and cpu ghost are not ordered in the same way so we have to reorder

		struct part
		{
			Point<3,float> xp;

			float prp0;
			float prp1[3];
			float prp2[3];

			bool operator<(const part & tmp) const
			{
				if (xp.get(0) < tmp.xp.get(0))
				{return true;}
				else if (xp.get(0) > tmp.xp.get(0))
				{return false;}

				if (xp.get(1) < tmp.xp.get(1))
				{return true;}
				else if (xp.get(1) > tmp.xp.get(1))
				{return false;}

				if (xp.get(2) < tmp.xp.get(2))
				{return true;}
				else if (xp.get(2) > tmp.xp.get(2))
				{return false;}

				return false;
			}
		};

		openfpm::vector<part> cpu_sort;
		openfpm::vector<part> gpu_sort;

		cpu_sort.resize(vd_cpu.size_local_with_ghost() - vd_cpu.size_local());
		gpu_sort.resize(vd.size_local_with_ghost() - vd.size_local());

		size_t cnt = 0;

		auto itc2 = vd.getGhostIterator();
		while (itc2.isNext())
		{
			auto p = itc2.get();

			cpu_sort.get(cnt).xp.get(0) = vd_cpu.getPos(p)[0];
			gpu_sort.get(cnt).xp.get(0) = vd.getPos(p)[0];
			cpu_sort.get(cnt).xp.get(1) = vd_cpu.getPos(p)[1];
			gpu_sort.get(cnt).xp.get(1) = vd.getPos(p)[1];
			cpu_sort.get(cnt).xp.get(2) = vd_cpu.getPos(p)[2];
			gpu_sort.get(cnt).xp.get(2) = vd.getPos(p)[2];

			cpu_sort.get(cnt).prp0 = vd_cpu.getProp<0>(p);
			gpu_sort.get(cnt).prp0 = vd.getProp<0>(p);

			cpu_sort.get(cnt).prp1[0] = vd_cpu.getProp<1>(p)[0];
			gpu_sort.get(cnt).prp1[0] = vd.getProp<1>(p)[0];
			cpu_sort.get(cnt).prp1[1] = vd_cpu.getProp<1>(p)[1];
			gpu_sort.get(cnt).prp1[1] = vd.getProp<1>(p)[1];
			cpu_sort.get(cnt).prp1[2] = vd_cpu.getProp<1>(p)[2];
			gpu_sort.get(cnt).prp1[2] = vd.getProp<1>(p)[2];

			cpu_sort.get(cnt).prp2[0] = vd_cpu.getProp<2>(p)[0];
			gpu_sort.get(cnt).prp2[0] = vd.getProp<2>(p)[0];
			cpu_sort.get(cnt).prp2[1] = vd_cpu.getProp<2>(p)[1];
			gpu_sort.get(cnt).prp2[1] = vd.getProp<2>(p)[1];
			cpu_sort.get(cnt).prp2[2] = vd_cpu.getProp<2>(p)[2];
			gpu_sort.get(cnt).prp2[2] = vd.getProp<2>(p)[2];

			++cnt;
			++itc2;
		}

		cpu_sort.sort();
		gpu_sort.sort();

		for (size_t i = 0 ; i < cpu_sort.size() ; i++)
		{
			match &= cpu_sort.get(i).xp.get(0) == gpu_sort.get(i).xp.get(0);
			match &= cpu_sort.get(i).xp.get(1) == gpu_sort.get(i).xp.get(1);
			match &= cpu_sort.get(i).xp.get(2) == gpu_sort.get(i).xp.get(2);

			match &= cpu_sort.get(i).prp0 == gpu_sort.get(i).prp0;
			match &= cpu_sort.get(i).prp1[0] == gpu_sort.get(i).prp1[0];
			match &= cpu_sort.get(i).prp1[1] == gpu_sort.get(i).prp1[1];
			match &= cpu_sort.get(i).prp1[2] == gpu_sort.get(i).prp1[2];

			match &= cpu_sort.get(i).prp2[0] == gpu_sort.get(i).prp2[0];
			match &= cpu_sort.get(i).prp2[1] == gpu_sort.get(i).prp2[1];
			match &= cpu_sort.get(i).prp2[2] == gpu_sort.get(i).prp2[2];
		}

		BOOST_REQUIRE_EQUAL(match,true);

		// move particles on gpu

		auto ite = vd.getDomainIteratorGPU();
		move_parts_gpu_test<3,decltype(vd.toKernel())><<<ite.wthr,ite.thr>>>(vd.toKernel());
	}*/
}


BOOST_AUTO_TEST_SUITE_END()

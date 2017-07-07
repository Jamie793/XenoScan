#pragma once
#include <map>
#include <memory>

template<typename K, typename A>
class KeyedFactory;

template<typename K, typename A>
class KeyedProducerBase
{
public:
	virtual const K& getKey() const = 0;
	virtual const std::shared_ptr<A> createInstance() const = 0;
	void registerTo(KeyedFactory<K, A>* factory)
	{
		factory->registerProducer(this);
	}
};

template<typename K, typename A, typename T>
class KeyedProducer : public KeyedProducerBase<K, A>
{
public:
	KeyedProducer(KeyedFactory<K, A>* factory)
	{
		this->registerTo(factory);
	}

	virtual const K& getKey() const
	{
		return T::Key;
	}

	virtual const std::shared_ptr<A> createInstance() const
	{
		return std::shared_ptr<A>(new T());
	}
};

template<typename K, typename A>
class KeyedFactory
{
friend class KeyedProducerBase<K, A>;
public:
	typedef const K KEY_TYPE;
	typedef A BASE_TYPE;

	KeyedFactory() {}
	const std::shared_ptr<A> createInstance(const K& key) const
	{
		auto producer = this->producers.find(key);
		if (producer != this->producers.end())
			return producer->second->createInstance();
		return nullptr;
	}

protected:
	void registerProducer(const KeyedProducerBase<K, A>* producer)
	{
		producers[producer->getKey()] = producer;
	}

private:
	std::map<K, const KeyedProducerBase<K, A>*> producers;
};

#define CREATE_FACTORY(CLASS) CLASS::FACTORY_TYPE CLASS::Factory;
#define CREATE_PRODUCER(CLASS, T, KEY) \
	CLASS::FACTORY_TYPE::KEY_TYPE T::Key = KEY;\
	const KeyedProducer<CLASS::FACTORY_TYPE::KEY_TYPE, CLASS::FACTORY_TYPE::BASE_TYPE, T> Keyed_ ## T ## _Producer(&CLASS::Factory);